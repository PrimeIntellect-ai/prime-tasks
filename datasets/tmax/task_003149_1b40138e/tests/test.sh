#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import socket
import subprocess
import threading

SOURCE_PATH = "/home/user/quota_monitor.rs"
BINARY_PATH = "/home/user/quota_monitor"
REBUILT_PATH = "/tmp/quota_monitor_rebuilt"
DATA_DIR = "/home/user/user_data"
TUNNEL_PATH = "/home/user/tunnel_cmd.sh"
EXPECTED_CMD = "ssh -N -f -L 5555:metrics.internal:80 admin@bastion.host"


def get_total_size(path):
    total_size = 0
    for dirpath, _, filenames in os.walk(path):
        for filename in filenames:
            file_path = os.path.join(dirpath, filename)
            if not os.path.islink(file_path):
                total_size += os.path.getsize(file_path)
    return total_size


def remove_tunnel():
    if os.path.lexists(TUNNEL_PATH):
        os.remove(TUNNEL_PATH)


def make_fixture(total):
    shutil.rmtree(DATA_DIR, ignore_errors=True)
    os.makedirs(os.path.join(DATA_DIR, "level1", "level2"), exist_ok=True)

    first = max(1, total // 5)
    second = max(1, total // 3)
    third = total - first - second
    assert third >= 0

    with open(os.path.join(DATA_DIR, "root.dat"), "wb") as f:
        f.truncate(first)
    with open(os.path.join(DATA_DIR, "level1", "middle.dat"), "wb") as f:
        f.truncate(second)
    with open(os.path.join(DATA_DIR, "level1", "level2", "deep.dat"), "wb") as f:
        f.truncate(third)

    assert get_total_size(DATA_DIR) == total


def run_failure(binary_path, expected_size):
    remove_tunnel()

    # Reserve the endpoint without listening. Connections reliably fail while
    # another process cannot race the verifier by binding the port.
    blocker = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    blocker.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    blocker.bind(("127.0.0.1", 5555))
    try:
        result = subprocess.run([binary_path], capture_output=True, text=True, timeout=10)
    finally:
        blocker.close()

    assert result.returncode == 0, (
        f"Running {binary_path} failed with return code {result.returncode}."
    )
    assert os.path.exists(TUNNEL_PATH), (
        f"{TUNNEL_PATH} was not created when connection failed at size {expected_size}."
    )
    with open(TUNNEL_PATH, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_CMD, (
        f"Expected '{EXPECTED_CMD}' in {TUNNEL_PATH}, but got '{content}'."
    )
    remove_tunnel()


def run_success(binary_path, expected_size):
    remove_tunnel()
    received_data = []
    server_errors = []

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 5555))
    server.listen(1)
    server.settimeout(5)

    def mock_server():
        try:
            conn, _ = server.accept()
            with conn:
                conn.settimeout(5)
                chunks = []
                while True:
                    chunk = conn.recv(1024)
                    if not chunk:
                        break
                    chunks.append(chunk)
                received_data.append(b"".join(chunks).decode("utf-8"))
        except Exception as exc:
            server_errors.append(exc)
        finally:
            server.close()

    thread = threading.Thread(target=mock_server)
    thread.start()
    result = subprocess.run([binary_path], capture_output=True, text=True, timeout=10)
    thread.join(timeout=7)

    assert not thread.is_alive(), "Mock metrics server did not finish."
    assert result.returncode == 0, (
        f"Running {binary_path} failed with return code {result.returncode}."
    )
    assert not server_errors, f"Mock metrics server failed: {server_errors}"
    assert len(received_data) > 0, "No data was received by the mock server on port 5555."
    expected_message = f"QUOTA_EXCEEDED:{expected_size}"
    assert received_data[0] == expected_message, (
        f"Expected to receive '{expected_message}', but got '{received_data[0]}'."
    )


def run_below_threshold(binary_path, total):
    remove_tunnel()
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 5555))
    server.listen(1)
    server.settimeout(1.5)
    try:
        result = subprocess.run([binary_path], capture_output=True, text=True, timeout=10)
        attempted_connection = False
        try:
            conn, _ = server.accept()
            attempted_connection = True
            conn.close()
        except socket.timeout:
            pass
    finally:
        server.close()

    assert result.returncode == 0, (
        f"Running {binary_path} below quota failed with return code {result.returncode}."
    )
    assert not attempted_connection, (
        f"{binary_path} connected to the metrics endpoint with only {total} bytes."
    )
    assert not os.path.exists(TUNNEL_PATH), (
        f"{TUNNEL_PATH} was created even though usage was only {total} bytes."
    )


def test_rust_source_exists_and_compiles():
    assert os.path.exists(SOURCE_PATH), (
        "Rust source file /home/user/quota_monitor.rs does not exist."
    )
    result = subprocess.run(
        ["rustc", SOURCE_PATH, "-o", REBUILT_PATH],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Rust source did not compile:\n{result.stderr}"
    assert os.access(REBUILT_PATH, os.X_OK), "Recompiled Rust program is not executable."


def test_rust_binary_exists_executable_and_native():
    assert os.path.exists(BINARY_PATH), f"Compiled binary {BINARY_PATH} does not exist."
    assert os.access(BINARY_PATH, os.X_OK), f"File {BINARY_PATH} is not executable."
    assert os.path.isfile(BINARY_PATH), f"File {BINARY_PATH} is not a regular file."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", (
            f"{BINARY_PATH} is not a native compiled ELF executable."
        )


def test_original_and_dynamic_behaviour():
    # Preserve the original verifier's 6,000-byte failure and success checks.
    make_fixture(6000)
    assert get_total_size(DATA_DIR) == 6000
    run_failure(BINARY_PATH, 6000)
    run_success(BINARY_PATH, 6000)

    # Exercise unpredictable recursive totals so a fixed response cannot pass.
    submitted_failure_total = 5001 + secrets.randbelow(7000)
    make_fixture(submitted_failure_total)
    run_failure(BINARY_PATH, submitted_failure_total)

    submitted_success_total = 5001 + secrets.randbelow(7000)
    make_fixture(submitted_success_total)
    run_success(BINARY_PATH, submitted_success_total)

    submitted_low_total = secrets.randbelow(5001)
    make_fixture(submitted_low_total)
    run_below_threshold(BINARY_PATH, submitted_low_total)

    # Also execute a fresh compilation of the submitted Rust source, ensuring
    # the source itself implements the required behavior rather than serving as
    # an unused decoy next to a separate executable.
    rebuilt_failure_total = 5001 + secrets.randbelow(7000)
    make_fixture(rebuilt_failure_total)
    run_failure(REBUILT_PATH, rebuilt_failure_total)

    rebuilt_success_total = 5001 + secrets.randbelow(7000)
    make_fixture(rebuilt_success_total)
    run_success(REBUILT_PATH, rebuilt_success_total)

    rebuilt_low_total = secrets.randbelow(5001)
    make_fixture(rebuilt_low_total)
    run_below_threshold(REBUILT_PATH, rebuilt_low_total)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
