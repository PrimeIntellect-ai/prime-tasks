#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import ssl
import stat
import subprocess
import tarfile
import tempfile
import time
import urllib.request
import uuid

import pytest

HOME = "/home/user"


def test_c_source_and_behavior():
    """Compile the submitted source and exercise its required interface and backup behavior."""
    source = f"{HOME}/backup_tool.c"
    assert os.path.isfile(source), f"{source} does not exist"

    with open(source, "r", encoding="utf-8", errors="replace") as f:
        text = f.read()
    uncommented = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)
    assert re.search(r"#\s*include\s*[<\"]sys/stat\.h[>\"]", uncommented), "backup_tool.c does not include <sys/stat.h>"
    assert re.search(r"\bstat\s*\(", uncommented), "backup_tool.c does not call stat()"
    assert re.search(r"\bsystem\s*\(", uncommented), "backup_tool.c does not call system()"

    with tempfile.TemporaryDirectory(prefix="verify_backup_") as td:
        executable = os.path.join(td, "submitted_backup_tool")
        compile_result = subprocess.run(
            ["gcc", source, "-o", executable],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert compile_result.returncode == 0, f"backup_tool.c failed to compile: {compile_result.stderr}"

        symbols = subprocess.check_output(["nm", "-D", executable], text=True, stderr=subprocess.STDOUT)
        assert re.search(r"\b(?:stat|__xstat)@", symbols), "compiled utility does not reference stat()"
        assert re.search(r"\bsystem@", symbols), "compiled utility does not reference system()"

        for args in ([], [td], [td, os.path.join(td, "x.tar.gz"), "extra"]):
            result = subprocess.run([executable, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
            assert result.returncode != 0, "backup_tool must reject any argument count other than exactly two"

        missing = os.path.join(td, "missing_" + uuid.uuid4().hex)
        missing_result = subprocess.run(
            [executable, missing, os.path.join(td, "missing.tar.gz")],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert missing_result.returncode == 1, "a nonexistent source must return exit status 1"
        assert missing_result.stderr, "a nonexistent source must print an error to stderr"

        source_dir = os.path.join(td, "source_" + uuid.uuid4().hex)
        os.mkdir(source_dir)
        filename = "payload_" + uuid.uuid4().hex + ".txt"
        payload = os.urandom(97)
        with open(os.path.join(source_dir, filename), "wb") as f:
            f.write(payload)
        archive = os.path.join(td, "result.tar.gz")

        result = subprocess.run(
            [executable, source_dir, archive],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, f"backup_tool failed for an existing source: {result.stderr.decode(errors='replace')}"
        assert os.path.isfile(archive), "backup_tool did not create the requested archive"
        with tarfile.open(archive, "r:gz") as tar:
            members = [m for m in tar.getmembers() if m.isfile() and os.path.basename(m.name) == filename]
            assert len(members) == 1, "archive does not contain the generated source file"
            assert tar.extractfile(members[0]).read() == payload, "archived data differs from the source data"


def test_pipeline_exists_and_executes_required_phases():
    """Run the submitted pipeline from a clean output state and inspect its executed commands."""
    pipeline = f"{HOME}/pipeline.sh"
    assert os.path.isfile(pipeline), f"{pipeline} does not exist"

    # Stop the server left by the agent so this execution must start its own listener.
    subprocess.run(["pkill", "-f", "[o]penssl s_server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)

    for path in (f"{HOME}/backup_tool", f"{HOME}/backups/latest.tar.gz", f"{HOME}/deploy.log"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    trace_path = f"/tmp/pipeline_trace_{uuid.uuid4().hex}"
    runner = 'exec 9>"$1"; export BASH_XTRACEFD=9; exec bash -x "$2"'
    started = time.time_ns()
    try:
        result = subprocess.run(
            ["runuser", "-u", "user", "--", "bash", "-c", runner, "pipeline-verifier", trace_path, pipeline],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
        assert result.returncode == 0, f"pipeline.sh exited with status {result.returncode}"
        time.sleep(1)
        with open(trace_path, "r", encoding="utf-8", errors="replace") as f:
            trace = f.read()
    finally:
        try:
            os.remove(trace_path)
        except FileNotFoundError:
            pass

    lines = [line[2:] for line in trace.splitlines() if line.startswith("+ ")]
    gcc_lines = [line for line in lines if re.search(r"(^|\s)gcc(\s|$)", line)]
    assert any("/home/user/backup_tool.c" in line and "/home/user/backup_tool" in line for line in gcc_lines), \
        "pipeline did not compile backup_tool.c into /home/user/backup_tool using gcc"

    tool_lines = [line for line in lines if re.search(r"(^|\s)/home/user/backup_tool(\s|$)", line)]
    assert any("/home/user/app_data" in line and "/home/user/backups/latest.tar.gz" in line for line in tool_lines), \
        "pipeline did not execute backup_tool with the required source and destination"

    assert any(re.search(r"(^|\s)cd\s+/home/user/backups(?:\s|$)", line) for line in lines), \
        "pipeline did not change into /home/user/backups before deployment"
    server_lines = [line for line in lines if re.search(r"(^|\s)openssl\s+s_server(?:\s|$)", line)]
    assert any(
        "-WWW" in line and "8443" in line and "/home/user/certs/server.crt" in line
        and "/home/user/certs/server.key" in line
        for line in server_lines
    ), "pipeline did not start the required openssl s_server command"
    assert any(re.search(r"(^|\s)echo\s+DEPLOYMENT SUCCESS(?:\s|$)", line) for line in lines), \
        "pipeline did not append the exact deployment success string"

    for path in (f"{HOME}/backup_tool", f"{HOME}/backups/latest.tar.gz", f"{HOME}/deploy.log"):
        assert os.path.exists(path), f"pipeline did not create {path}"
        assert os.stat(path).st_mtime_ns >= started, f"{path} was not recreated by this pipeline execution"

    deadline = time.time() + 8
    listener_output = ""
    while time.time() < deadline:
        listener_output = subprocess.run(
            ["ss", "-tlnp"], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        ).stdout
        if ":8443" in listener_output and "openssl" in listener_output:
            break
        time.sleep(0.25)
    assert ":8443" in listener_output and "openssl" in listener_output, \
        "pipeline did not leave openssl s_server listening on port 8443"


def test_directories_and_permissions():
    """Verify directories are created and /home/user/backups has strict permissions."""
    assert os.path.isdir("/home/user/app_data"), "/home/user/app_data does not exist"
    assert os.path.isdir("/home/user/backups"), "/home/user/backups does not exist"
    assert os.path.isdir("/home/user/certs"), "/home/user/certs does not exist"

    st = os.stat("/home/user/backups")
    assert oct(st.st_mode)[-3:] == "700", "/home/user/backups does not have 700 permissions"


def test_config_file():
    """Verify config.txt exists and contains the correct string."""
    config_path = "/home/user/app_data/config.txt"
    assert os.path.isfile(config_path), f"{config_path} does not exist"
    with open(config_path, "r") as f:
        content = f.read()
    assert "db_port=5432" in content, f"{config_path} does not contain 'db_port=5432'"


def test_tls_certificates():
    """Verify TLS cert and key exist and key has strict permissions."""
    cert_path = "/home/user/certs/server.crt"
    key_path = "/home/user/certs/server.key"

    assert os.path.isfile(cert_path), f"{cert_path} does not exist"
    assert os.path.isfile(key_path), f"{key_path} does not exist"

    st = os.stat(key_path)
    assert oct(st.st_mode)[-3:] == "600", f"{key_path} does not have 600 permissions"


def test_c_tool_and_binary():
    """Verify the C source and compiled binary exist."""
    assert os.path.isfile("/home/user/backup_tool.c"), "/home/user/backup_tool.c does not exist"
    assert os.path.isfile("/home/user/backup_tool"), "/home/user/backup_tool does not exist"
    assert os.access("/home/user/backup_tool", os.X_OK), "/home/user/backup_tool is not executable"


def test_backup_archive():
    """Verify the backup archive exists and contains config.txt."""
    archive_path = "/home/user/backups/latest.tar.gz"
    assert os.path.isfile(archive_path), f"{archive_path} does not exist"

    with tarfile.open(archive_path, "r:gz") as tar:
        names = tar.getnames()
        assert any("config.txt" in name for name in names), "config.txt not found in the backup archive"


def test_deployment_log():
    """Verify the deployment log has the success message."""
    log_path = "/home/user/deploy.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist"
    with open(log_path, "r") as f:
        content = f.read()
    assert "DEPLOYMENT SUCCESS" in content, "DEPLOYMENT SUCCESS not found in deploy.log"


def test_server_running_and_serving():
    """Verify the openssl server is running on port 8443 and serves the backup archive."""
    try:
        output = subprocess.check_output(["ss", "-tlnp"], text=True)
        assert ":8443" in output, "Server is not listening on port 8443"
    except FileNotFoundError:
        pass

    url = "https://127.0.0.1:8443/latest.tar.gz"
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            data = response.read()
            assert len(data) > 0, "Downloaded file is empty"
    except Exception as e:
        pytest.fail(f"Failed to download the backup archive from the secure server: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
