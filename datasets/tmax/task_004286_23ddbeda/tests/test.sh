#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import secrets
import signal
import socket
import stat
import subprocess
import tarfile
import threading
import time

import pytest

TARBALL = "/home/user/archive/network_diag.tar.gz"
SOURCE = "/home/user/network_diag/diag.cpp"
SCRIPT = "/home/user/run_pipeline.sh"
BUILD_DIR = "/home/user/build"
EXECUTABLE = "/home/user/build/diag_tool"
LOG = "/home/user/pipeline.log"

ORIGINAL_SOURCE = b'''#include <iostream>
#include <string>
#include <unistd.h>
#include <ctime>
#include <cstring>
// Missing network headers intentionally:
// #include <sys/socket.h>
// #include <arpa/inet.h>

int main() {
    int sock = 0;
    struct sockaddr_in serv_addr;
    char buffer[1024] = {0};

    if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
        std::cerr << "Socket creation error" << std::endl;
        return -1;
    }

    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(9999);

    if (inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr) <= 0) {
        std::cerr << "Invalid address/ Address not supported" << std::endl;
        return -1;
    }

    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        std::cerr << "Connection Failed" << std::endl;
        return -1;
    }

    read(sock, buffer, 1024);

    // Time formatting
    std::time_t t = std::time(nullptr);
    char time_buf[100];
    // Needs to use gmtime and format exactly to YYYY-MM-DD HH:MM:SS
    std::strftime(time_buf, sizeof(time_buf), "%Y-%m-%d %H:%M:%S", std::gmtime(&t));

    // Remove potential newlines from buffer
    std::string response(buffer);
    if (!response.empty() && response.back() == '\n') {
        response.pop_back();
    }

    std::cout << "[" << time_buf << "] STATUS: " << response << std::endl;
    close(sock);
    return 0;
}
'''

OUTPUT_RE = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] STATUS: ([^\r\n]+)$")


def assert_utc_output(output, expected_response):
    text = output.strip()
    match = OUTPUT_RE.fullmatch(text)
    assert match, f"Output {text!r} does not have the required exact format"
    assert match.group(2) == expected_response, (
        f"Expected socket response {expected_response!r}, got {match.group(2)!r}"
    )
    timestamp = datetime.datetime.strptime(
        match.group(1), "%Y-%m-%d %H:%M:%S"
    ).replace(tzinfo=datetime.timezone.utc)
    now = datetime.datetime.now(datetime.timezone.utc)
    assert abs((now - timestamp).total_seconds()) <= 10, (
        f"Timestamp {match.group(1)!r} is not the current UTC time"
    )


def exercise_binary(path, response):
    ready = threading.Event()
    errors = []

    def server():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
                listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                listener.bind(("127.0.0.1", 9999))
                listener.listen(1)
                listener.settimeout(8)
                ready.set()
                conn, _ = listener.accept()
                with conn:
                    conn.sendall((response + "\n").encode())
        except BaseException as exc:
            errors.append(exc)
            ready.set()

    thread = threading.Thread(target=server, daemon=True)
    thread.start()
    assert ready.wait(3), "Test endpoint did not become ready"
    assert not errors, f"Could not listen on 127.0.0.1:9999: {errors[0]}"

    env = os.environ.copy()
    # A local-time implementation would be many hours away from UTC here.
    env["TZ"] = "Pacific/Honolulu"
    result = subprocess.run(
        [path], capture_output=True, text=True, env=env, timeout=10
    )
    thread.join(3)
    assert not thread.is_alive(), "The tool did not connect to the test endpoint"
    assert not errors, f"Socket test failed: {errors[0]}"
    assert result.returncode == 0, (
        f"Tool exited with {result.returncode}; stderr: {result.stderr!r}"
    )
    assert result.stderr == "", f"Tool unexpectedly wrote stderr: {result.stderr!r}"
    assert_utc_output(result.stdout, response)


def test_00_execute_pipeline_and_exercise_artifacts():
    assert os.path.isfile(SCRIPT), f"Pipeline script not found at {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Pipeline script at {SCRIPT} is not executable"
    assert os.path.isfile(SOURCE), f"Source file not found at {SOURCE}"

    with open(SOURCE, "r", encoding="utf-8") as source_file:
        source = source_file.read()
    assert "sys/socket.h" in source, "diag.cpp is missing the standard socket header"
    assert "arpa/inet.h" in source, "diag.cpp is missing the IPv4 networking header"
    assert "gmtime" in source, "diag.cpp does not request UTC broken-down time"
    assert "127.0.0.1" in source and "9999" in source, (
        "diag.cpp does not target 127.0.0.1 port 9999"
    )

    with open(SCRIPT, "r", encoding="utf-8") as script_file:
        script_text = script_file.read()
    for required in ("g++", "diag.cpp", "diag_tool", "nc", "9999", "ALL_CLEAR", "TZ", "UTC", "pipeline.log"):
        assert required in script_text, f"Pipeline script does not contain required pipeline element {required!r}"

    # Remove fabricated/stale outputs so the script must recreate them itself.
    if os.path.lexists(LOG):
        os.remove(LOG)
    if os.path.isdir(BUILD_DIR) and not os.path.islink(BUILD_DIR):
        subprocess.run(["rm", "-rf", BUILD_DIR], check=True)
    elif os.path.lexists(BUILD_DIR):
        os.remove(BUILD_DIR)

    env = os.environ.copy()
    env["TZ"] = "Pacific/Honolulu"
    started = time.time()
    proc = subprocess.Popen(
        [SCRIPT], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        stdout, stderr = proc.communicate()
        pytest.fail(f"Pipeline timed out; stdout={stdout!r}, stderr={stderr!r}")
    assert proc.returncode == 0, (
        f"Pipeline exited with {proc.returncode}; stdout={stdout!r}, stderr={stderr!r}"
    )

    assert os.path.isdir(BUILD_DIR), f"Build directory not created at {BUILD_DIR}"
    assert os.path.isfile(EXECUTABLE), f"Pipeline did not create {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"Compiled tool at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as executable_file:
        assert executable_file.read(4) == b"\x7fELF", "diag_tool is not a compiled ELF executable"

    assert os.path.isfile(LOG), f"Pipeline did not create {LOG}"
    assert os.path.getmtime(LOG) >= started - 1, "pipeline.log was not freshly generated"
    with open(LOG, "r", encoding="utf-8") as log_file:
        pipeline_output = log_file.read()
    assert_utc_output(pipeline_output, "ALL_CLEAR")

    # Use unpredictable responses so a hard-coded ALL_CLEAR program cannot pass.
    exercise_binary(EXECUTABLE, "VERIFY_" + secrets.token_hex(8))

    # Independently compile the submitted source, proving diag.cpp itself works.
    rebuilt = "/tmp/diag_tool_from_submitted_source"
    compile_result = subprocess.run(
        ["g++", SOURCE, "-o", rebuilt], capture_output=True, text=True, timeout=20
    )
    assert compile_result.returncode == 0, (
        f"Submitted diag.cpp does not compile: {compile_result.stderr!r}"
    )
    exercise_binary(rebuilt, "SOURCE_" + secrets.token_hex(8))


def test_backup_tarball_exists_and_valid():
    """Verify the backup is a valid archive containing the original diag.cpp."""
    assert os.path.isfile(TARBALL), f"Backup tarball not found at {TARBALL}"
    try:
        with tarfile.open(TARBALL, "r:gz") as tar:
            members = [
                member for member in tar.getmembers()
                if member.isfile() and member.name.rstrip("/").endswith("network_diag/diag.cpp")
            ]
            assert members, f"diag.cpp not found in the backup tarball {TARBALL}"
            archived = tar.extractfile(members[0]).read()
            assert archived == ORIGINAL_SOURCE, (
                "The backup does not contain the original pre-modification diag.cpp"
            )
    except tarfile.TarError as exc:
        pytest.fail(f"Failed to open tarball {TARBALL}: {exc}")


def test_pipeline_script_executable():
    """Verify that the run_pipeline.sh script exists and is executable."""
    assert os.path.isfile(SCRIPT), f"Pipeline script not found at {SCRIPT}"
    st = os.stat(SCRIPT)
    is_executable = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
    assert is_executable, f"Pipeline script at {SCRIPT} is not executable"


def test_pipeline_log_exists_and_correct():
    """Verify that the pipeline log contains the required formatted output."""
    assert os.path.isfile(LOG), f"Pipeline log not found at {LOG}"
    with open(LOG, "r", encoding="utf-8") as log_file:
        content = log_file.read().strip()
    pattern = r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] STATUS: ALL_CLEAR$"
    assert re.match(pattern, content), (
        f"Pipeline log content {content!r} does not match the expected format."
    )


def test_build_directory_and_executable():
    """Verify that the build directory and compiled executable exist."""
    assert os.path.isdir(BUILD_DIR), f"Build directory not found at {BUILD_DIR}"
    assert os.path.isfile(EXECUTABLE), f"Compiled executable not found at {EXECUTABLE}"
    st = os.stat(EXECUTABLE)
    is_executable = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
    assert is_executable, f"Compiled tool at {EXECUTABLE} is not executable"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
