#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import socket
import stat
import subprocess
import time

import pytest

SCRIPT_PATH = "/home/user/test_restore.sh"
VERIFIER_SRC = "/home/user/verifier.cpp"
VERIFIER_BIN = "/home/user/verifier"
DISK_CHECK_LOG = "/home/user/disk_check.txt"
RESTORE_LOG = "/home/user/restore_log.txt"
PAYLOAD_BIN = "/home/user/restores/payload.bin"
TEST_COMPILED_BIN = "/tmp/student_verifier_test"


@pytest.fixture(scope="session", autouse=True)
def run_student_script():
    """Run the student's script before checking the final state."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."

    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def test_script_executable():
    """Verify the script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"File {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"File {SCRIPT_PATH} is not executable."


def test_verifier_artifacts_exist():
    """Verify that the requested C++ source and compiled executable exist."""
    assert os.path.isfile(VERIFIER_SRC), f"C++ source {VERIFIER_SRC} is missing."
    assert os.path.isfile(VERIFIER_BIN), f"Compiled verifier {VERIFIER_BIN} is missing."
    assert os.access(VERIFIER_BIN, os.X_OK), f"Compiled verifier {VERIFIER_BIN} is not executable."
    with open(VERIFIER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{VERIFIER_BIN} is not a compiled ELF executable."


def test_disk_check_output():
    """Verify disk_check.txt contains df output."""
    assert os.path.isfile(DISK_CHECK_LOG), f"File {DISK_CHECK_LOG} is missing."
    with open(DISK_CHECK_LOG, "r") as f:
        content = f.read()
    assert "Filesystem" in content or "1K-blocks" in content, (
        f"{DISK_CHECK_LOG} does not appear to contain 'df' output."
    )


def test_payload_bin_size():
    """Verify payload.bin exists and is exactly 1024 bytes."""
    assert os.path.isfile(PAYLOAD_BIN), f"File {PAYLOAD_BIN} is missing."
    size = os.path.getsize(PAYLOAD_BIN)
    assert size == 1024, f"File {PAYLOAD_BIN} size is {size} bytes, expected exactly 1024 bytes."


def test_restore_log_content():
    """Verify restore_log.txt contains the correct success message."""
    assert os.path.isfile(RESTORE_LOG), f"File {RESTORE_LOG} is missing."
    with open(RESTORE_LOG, "r") as f:
        content = f.read()
    assert content == "RESTORE VERIFIED: 1024 BYTES\n", (
        f"Incorrect content in {RESTORE_LOG}. Got: {content!r}"
    )


def test_no_lingering_verifier_process():
    """Verify that the verifier process exited cleanly and is not running."""
    try:
        result = subprocess.run(["pgrep", "-f", VERIFIER_BIN], capture_output=True, text=True)
        assert result.returncode != 0, (
            f"Lingering '{VERIFIER_BIN}' process found. It should have exited cleanly."
        )
    except FileNotFoundError:
        result = subprocess.run(["ps", "-A"], capture_output=True, text=True)
        assert "verifier" not in result.stdout, "Lingering 'verifier' process found in ps output."


def compile_source():
    try:
        os.unlink(TEST_COMPILED_BIN)
    except FileNotFoundError:
        pass
    result = subprocess.run(
        ["g++", VERIFIER_SRC, "-o", TEST_COMPILED_BIN],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"verifier.cpp does not compile.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    assert os.path.isfile(TEST_COMPILED_BIN)
    assert os.access(TEST_COMPILED_BIN, os.X_OK)


def exercise_server(executable, byte_count):
    try:
        os.unlink(RESTORE_LOG)
    except FileNotFoundError:
        pass

    proc = subprocess.Popen(executable, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    client = None
    try:
        deadline = time.monotonic() + 4
        last_error = None
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                out, err = proc.communicate()
                pytest.fail(
                    f"{executable} exited before accepting a TCP connection. "
                    f"Exit code: {proc.returncode}\nSTDOUT:\n{out}\nSTDERR:\n{err}"
                )
            try:
                client = socket.create_connection(("127.0.0.1", 9090), timeout=0.5)
                break
            except OSError as exc:
                last_error = exc
                time.sleep(0.05)
        assert client is not None, f"{executable} did not listen on 127.0.0.1:9090: {last_error}"

        payload = os.urandom(byte_count)
        offset = 0
        while offset < len(payload):
            chunk_size = min(len(payload) - offset, random.SystemRandom().randint(1, 97))
            client.sendall(payload[offset:offset + chunk_size])
            offset += chunk_size
        client.shutdown(socket.SHUT_WR)
        client.close()
        client = None

        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pytest.fail(f"{executable} did not exit after the client closed the connection.")
        out, err = proc.communicate()
        assert proc.returncode == 0, (
            f"{executable} exited with {proc.returncode}.\nSTDOUT:\n{out}\nSTDERR:\n{err}"
        )

        assert os.path.isfile(RESTORE_LOG), f"{executable} did not create {RESTORE_LOG}."
        with open(RESTORE_LOG, "r") as f:
            actual = f.read()
        if byte_count == 1024:
            expected = "RESTORE VERIFIED: 1024 BYTES\n"
        else:
            expected = f"RESTORE FAILED: {byte_count} BYTES\n"
        assert actual == expected, (
            f"Wrong result after sending {byte_count} bytes to {executable}: "
            f"expected {expected!r}, got {actual!r}"
        )
    finally:
        if client is not None:
            client.close()
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=2)
        time.sleep(0.05)


def test_verifier_network_behavior_and_source():
    """Compile the submitted source and exercise both produced executables over TCP."""
    compile_source()
    rng = random.SystemRandom()
    counts = [0, rng.randint(1, 1023), rng.randint(1025, 4096), 1024]
    for executable in (VERIFIER_BIN, TEST_COMPILED_BIN):
        for count in counts:
            exercise_server(executable, count)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
