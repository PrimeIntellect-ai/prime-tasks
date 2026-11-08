#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import os
import secrets
import shutil
import socket
import stat
import subprocess
import tempfile

import pytest

SOURCE_PATH = "/home/user/infra_agent.rs"
BINARY_PATH = "/home/user/infra_agent"
STORAGE_PATH = "/home/user/app_storage"
LOG_PATH = "/home/user/health.log"
UNIT_FILE_PATH = "/home/user/.config/systemd/user/infra_agent.service"


def clear_log():
    if os.path.lexists(LOG_PATH):
        if os.path.isdir(LOG_PATH) and not os.path.islink(LOG_PATH):
            shutil.rmtree(LOG_PATH)
        else:
            os.remove(LOG_PATH)


def log_content():
    if not os.path.exists(LOG_PATH):
        return None
    with open(LOG_PATH, "r") as f:
        return f.read()


@contextlib.contextmanager
def listening_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", 8888))
    s.listen(8)
    try:
        yield
    finally:
        s.close()


@contextlib.contextmanager
def non_listening_port():
    # Holding a bound TCP socket without listening guarantees that attempts to
    # connect to the required port fail while preventing another listener from
    # appearing during the test.
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", 8888))
    try:
        yield
    finally:
        s.close()


@contextlib.contextmanager
def storage_absent():
    backup = STORAGE_PATH + ".verifier_backup_" + secrets.token_hex(8)
    existed = os.path.lexists(STORAGE_PATH)
    if existed:
        os.rename(STORAGE_PATH, backup)
    try:
        yield
    finally:
        if os.path.lexists(STORAGE_PATH):
            if os.path.isdir(STORAGE_PATH) and not os.path.islink(STORAGE_PATH):
                shutil.rmtree(STORAGE_PATH)
            else:
                os.remove(STORAGE_PATH)
        if existed:
            os.rename(backup, STORAGE_PATH)
        else:
            os.makedirs(STORAGE_PATH, exist_ok=True)


def execute(binary, user_value, user_is_set=True):
    env = os.environ.copy()
    if user_is_set:
        env["USER"] = user_value
    else:
        env.pop("USER", None)
    try:
        subprocess.run([binary], env=env, timeout=3, check=False)
    except Exception as e:
        pytest.fail(f"Failed to execute {binary}: {e}")


def assert_no_ready(binary, user_value="user", user_is_set=True, listener=True):
    clear_log()
    manager = listening_port() if listener else non_listening_port()
    with manager:
        execute(binary, user_value, user_is_set)
    content = log_content()
    assert content is None or content == "", (
        f"{binary} wrote to {LOG_PATH} when a required health check failed: {content!r}"
    )


def exercise_behavior(binary):
    os.makedirs(STORAGE_PATH, exist_ok=True)

    # Incorrect and missing USER must both suppress readiness, even when the
    # other two checks succeed.
    assert_no_ready(binary, "not-user-" + secrets.token_hex(12), True, True)
    assert_no_ready(binary, user_is_set=False, listener=True)

    # Missing storage must suppress readiness while USER and connectivity pass.
    with storage_absent():
        assert_no_ready(binary, "user", True, True)

    # Failed connectivity must suppress readiness while USER and storage pass.
    os.makedirs(STORAGE_PATH, exist_ok=True)
    assert_no_ready(binary, "user", True, False)

    # All three successful checks must append exactly the required line.
    clear_log()
    with listening_port():
        execute(binary, "user", True)
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} was not created by {binary}."
    content = log_content()
    assert "SYSTEM_READY" in content, (
        f"Expected 'SYSTEM_READY' in {LOG_PATH}, but got {content!r}"
    )
    assert content == "SYSTEM_READY\n", (
        f"Expected exactly 'SYSTEM_READY\\n' from a clean log, but got {content!r}"
    )


@pytest.fixture(scope="session")
def rebuilt_binary():
    assert os.path.isfile(SOURCE_PATH), f"Rust source {SOURCE_PATH} does not exist."
    fd, output = tempfile.mkstemp(prefix="infra_agent_rebuilt_", dir="/tmp")
    os.close(fd)
    os.remove(output)
    try:
        result = subprocess.run(
            ["rustc", SOURCE_PATH, "-o", output],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
    except Exception as e:
        pytest.fail(f"Failed to invoke rustc on {SOURCE_PATH}: {e}")
    assert result.returncode == 0, f"rustc failed for {SOURCE_PATH}: {result.stderr}"
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    yield output
    if os.path.exists(output):
        os.remove(output)


def test_binary_exists_and_executable():
    assert os.path.exists(BINARY_PATH), f"Binary {BINARY_PATH} does not exist."
    assert os.path.isfile(BINARY_PATH), f"Binary {BINARY_PATH} is not a regular file."
    assert os.access(BINARY_PATH, os.X_OK), f"Binary {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        data = f.read()
    assert data.startswith(b"\x7fELF"), f"{BINARY_PATH} is not a compiled ELF executable."
    rust_markers = (b"rust_eh_personality", b"rust_begin_unwind", b"/rustc/", b"library/std/src")
    assert any(marker in data for marker in rust_markers), (
        f"{BINARY_PATH} does not contain normal Rust executable metadata."
    )


def test_binary_behavior():
    exercise_behavior(BINARY_PATH)


def test_rust_source_compiles_and_behaves(rebuilt_binary):
    exercise_behavior(rebuilt_binary)


def test_systemd_unit_file():
    assert os.path.exists(UNIT_FILE_PATH), f"systemd unit file {UNIT_FILE_PATH} not found."

    with open(UNIT_FILE_PATH, "r") as f:
        content = f.read()

    assert "[Service]" in content, "Unit file missing [Service] section."

    exec_start_found = False
    restart_always_found = False

    for line in content.splitlines():
        line = line.strip()
        if line.startswith("ExecStart="):
            parts = line.split("=", 1)
            if parts[1].strip() == BINARY_PATH:
                exec_start_found = True
        if line.lower().startswith("restart="):
            parts = line.split("=", 1)
            if parts[1].strip().lower() == "always":
                restart_always_found = True

    assert exec_start_found, f"Unit file missing correct ExecStart={BINARY_PATH}"
    assert restart_always_found, "Unit file missing Restart=always"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
