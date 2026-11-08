#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import re
import socket
import subprocess
import threading
import time

import pytest

HOME_DIR = "/home/user"
NETWORK_ENV = os.path.join(HOME_DIR, "network_env.sh")
FORWARDER = os.path.join(HOME_DIR, "forwarder.py")
CHECK_QUOTA = os.path.join(HOME_DIR, "check_quota.py")
RUN_TEST = os.path.join(HOME_DIR, "run_test.sh")
LOG_DIR = os.path.join(HOME_DIR, "logs")
FORWARDER_LOG = os.path.join(LOG_DIR, "forwarder.log")
QUOTA_STATUS = os.path.join(HOME_DIR, "quota_status.txt")


def test_files_exist_and_executable():
    """Ensure all required scripts are created and executable."""
    required_files = [NETWORK_ENV, FORWARDER, CHECK_QUOTA, RUN_TEST]
    for f in required_files:
        assert os.path.isfile(f), f"Required file {f} does not exist."
        assert os.access(f, os.X_OK), f"File {f} is not executable."


def test_network_env_vars():
    """Ensure network_env.sh exports the correct variables."""
    cmd = f"source {NETWORK_ENV} && env"
    result = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to source {NETWORK_ENV}"

    env_output = result.stdout
    assert "FWD_LISTEN_PORT=8080" in env_output, "FWD_LISTEN_PORT not correctly exported."
    assert "FWD_TARGET_PORT=9090" in env_output, "FWD_TARGET_PORT not correctly exported."
    assert f"LOG_DIR={LOG_DIR}" in env_output, "LOG_DIR not correctly exported."


def test_forwarder_script_contents():
    """Ensure forwarder.py contains the correct RotatingFileHandler setup."""
    with open(FORWARDER, "r") as f:
        content = f.read()

    assert "RotatingFileHandler" in content, "forwarder.py does not use RotatingFileHandler."
    assert re.search(r"maxBytes\s*=\s*512", content), "forwarder.py does not set maxBytes=512."
    assert re.search(r"backupCount\s*=\s*2", content), "forwarder.py does not set backupCount=2."


def test_run_test_sh_execution():
    """Execute run_test.sh and verify it runs successfully."""
    result = subprocess.run(["bash", RUN_TEST], capture_output=True, text=True)
    assert result.returncode == 0, f"run_test.sh failed to execute properly. Stderr: {result.stderr}"


def test_logs_created_and_populated():
    """Ensure the log file is created and contains the expected log message."""
    assert os.path.isdir(LOG_DIR), f"Log directory {LOG_DIR} was not created."
    assert os.path.isfile(FORWARDER_LOG), f"Log file {FORWARDER_LOG} was not created."

    with open(FORWARDER_LOG, "r") as f:
        log_content = f.read()

    assert "New connection established" in log_content, "The expected log message 'New connection established' was not found in the forwarder log."


def test_quota_status():
    """Ensure the quota status file is created and contains the correct initial state."""
    assert os.path.isfile(QUOTA_STATUS), f"Quota status file {QUOTA_STATUS} was not created."

    with open(QUOTA_STATUS, "r") as f:
        status = f.read().strip()

    assert status == "QUOTA_OK", f"Expected quota status 'QUOTA_OK', but found '{status}'."


def test_forwarder_actually_proxies_and_rotates_logs(tmp_path):
    """Exercise bidirectional TCP forwarding using independently generated data."""
    log_dir = tmp_path / "proxy_logs"
    log_dir.mkdir()

    target = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    target.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    target.bind(("127.0.0.1", 0))
    target.listen()
    target.settimeout(0.2)
    target_port = target.getsockname()[1]

    reserve = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    reserve.bind(("127.0.0.1", 0))
    listen_port = reserve.getsockname()[1]
    reserve.close()

    stop_server = threading.Event()
    server_errors = []

    def serve():
        while not stop_server.is_set():
            try:
                conn, _ = target.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            try:
                with conn:
                    conn.settimeout(5)
                    chunks = []
                    while True:
                        data = conn.recv(4096)
                        if not data:
                            break
                        chunks.append(data)
                    request = b"".join(chunks)
                    response = b"TARGET:" + hashlib.sha256(request).digest() + request[::-1]
                    conn.sendall(response)
            except Exception as exc:
                server_errors.append(repr(exc))

    server_thread = threading.Thread(target=serve, daemon=True)
    server_thread.start()

    env = os.environ.copy()
    env.update({
        "FWD_LISTEN_PORT": str(listen_port),
        "FWD_TARGET_PORT": str(target_port),
        "LOG_DIR": str(log_dir),
    })
    proc = subprocess.Popen(
        ["python3", FORWARDER],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    try:
        for index in range(40):
            payload = os.urandom(173 + index) + index.to_bytes(2, "big")
            expected = b"TARGET:" + hashlib.sha256(payload).digest() + payload[::-1]
            deadline = time.time() + 8
            last_error = None

            while time.time() < deadline:
                try:
                    with socket.create_connection(("127.0.0.1", listen_port), timeout=2) as client:
                        client.settimeout(5)
                        client.sendall(payload)
                        client.shutdown(socket.SHUT_WR)
                        received = bytearray()
                        while len(received) < len(expected):
                            chunk = client.recv(4096)
                            if not chunk:
                                break
                            received.extend(chunk)
                    assert bytes(received) == expected
                    last_error = None
                    break
                except (ConnectionRefusedError, ConnectionResetError, socket.timeout, OSError) as exc:
                    last_error = exc
                    if proc.poll() is not None:
                        stdout, stderr = proc.communicate()
                        pytest.fail(f"forwarder.py exited early ({proc.returncode}). stdout={stdout!r} stderr={stderr!r}")
                    time.sleep(0.1)
            assert last_error is None, f"Could not exchange data through forwarder: {last_error}"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
        stop_server.set()
        target.close()
        server_thread.join(timeout=2)

    assert not server_errors, f"Destination server errors: {server_errors}"
    log_files = sorted(glob.glob(str(log_dir / "forwarder.log*")))
    assert str(log_dir / "forwarder.log") in log_files
    assert str(log_dir / "forwarder.log.1") in log_files, "Traffic did not trigger log rotation."
    assert len(log_files) <= 3, "More than two rotated backups were retained."
    assert not os.path.exists(log_dir / "forwarder.log.3")
    assert all(os.path.getsize(path) <= 512 for path in log_files), "A forwarding log exceeded maxBytes=512."
    combined_logs = "".join(open(path, encoding="utf-8", errors="replace").read() for path in log_files)
    assert "New connection established" in combined_logs


def test_quota_calculation_at_and_above_threshold(tmp_path):
    """Derive quota expectations from independently created files."""
    quota_dir = tmp_path / "quota_logs"
    quota_dir.mkdir()
    env = os.environ.copy()
    env["LOG_DIR"] = str(quota_dir)

    (quota_dir / "part_a.bin").write_bytes(os.urandom(600))
    (quota_dir / "part_b.bin").write_bytes(os.urandom(424))
    if os.path.exists(QUOTA_STATUS):
        os.unlink(QUOTA_STATUS)

    result = subprocess.run([CHECK_QUOTA], env=env, capture_output=True, text=True)
    assert result.returncode == 0, f"check_quota.py failed: {result.stderr}"
    with open(QUOTA_STATUS, "r") as f:
        assert f.read().strip() == "QUOTA_OK", "Exactly 1024 bytes must be within quota."

    (quota_dir / "part_c.bin").write_bytes(os.urandom(1))
    result = subprocess.run([CHECK_QUOTA], env=env, capture_output=True, text=True)
    assert result.returncode == 0, f"check_quota.py failed: {result.stderr}"
    with open(QUOTA_STATUS, "r") as f:
        assert f.read().strip() == "QUOTA_EXCEEDED", "A combined size of 1025 bytes must exceed quota."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
