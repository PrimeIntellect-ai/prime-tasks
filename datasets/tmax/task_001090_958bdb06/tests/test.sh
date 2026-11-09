#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import socket
import stat
import subprocess
import time
import pytest


def test_task_done_file():
    """Verify that the task_done.txt file exists."""
    path = "/home/user/task_done.txt"
    assert os.path.exists(path), f"File {path} does not exist. Did you forget to create it?"
    assert os.path.isfile(path), f"Path {path} is not a regular file."


def test_app_metrics_log():
    """Verify that the app_metrics.log exists and contains the original test payload."""
    path = "/home/user/app_metrics.log"
    assert os.path.exists(path), f"Log file {path} does not exist. The end-to-end test may not have executed correctly."

    with open(path, "r") as f:
        content = f.read()

    assert "TEST_RESTORE_METRIC: SUCCESS_42" in content, (
        f"The expected payload was not found in {path}. "
        "Check if port forwarding and the daemon were working correctly."
    )


def test_metrics_daemon_executable():
    """Verify that the metrics_daemon was compiled and is an ELF executable."""
    exe_path = "/home/user/restore/metrics_daemon"
    assert os.path.exists(exe_path), f"Executable {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."

    with open(exe_path, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"File {exe_path} is not a valid ELF binary."


def test_logrotate_config():
    """Verify that the logrotate configuration contains the required directives."""
    path = "/home/user/logrotate.conf"
    assert os.path.exists(path), f"Logrotate configuration {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "/home/user/app_metrics.log" in content, "Logrotate config must target /home/user/app_metrics.log"
    assert re.search(r'\bhourly\b', content), "Directive 'hourly' is missing from logrotate config."
    assert re.search(r'\brotate\s+5\b', content), "Directive 'rotate 5' is missing from logrotate config."
    assert re.search(r'\bcompress\b', content), "Directive 'compress' is missing from logrotate config."
    assert re.search(r'\bmissingok\b', content), "Directive 'missingok' is missing from logrotate config."


def test_metrics_daemon_source_fixed():
    """Verify that the C++ source code was updated with the new socket path."""
    src_path = "/home/user/restore/metrics_daemon.cpp"
    assert os.path.exists(src_path), f"Source file {src_path} does not exist."

    with open(src_path, "r") as f:
        content = f.read()

    assert "/home/user/app.sock" in content, (
        f"The new socket path '/home/user/app.sock' was not found in {src_path}."
    )
    assert "/home/user/old.sock" not in content, (
        f"The old socket path '/home/user/old.sock' is still present in {src_path}."
    )


def test_live_tcp_to_unix_forwarding_and_daemon_logging():
    """Run the submitted daemon and exercise TCP-to-UNIX forwarding with a fresh payload."""
    exe_path = "/home/user/restore/metrics_daemon"
    unix_path = "/home/user/app.sock"
    log_path = "/home/user/app_metrics.log"
    payload = f"VERIFIER_RESTORE_METRIC_{secrets.token_hex(16)}"

    before = b""
    if os.path.exists(log_path):
        with open(log_path, "rb") as f:
            before = f.read()

    try:
        os.unlink(unix_path)
    except FileNotFoundError:
        pass

    daemon = None
    forwarder = None
    try:
        daemon = subprocess.Popen(
            [exe_path],
            cwd="/home/user/restore",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        deadline = time.time() + 4
        while time.time() < deadline:
            if daemon.poll() is not None:
                out, err = daemon.communicate()
                pytest.fail(f"metrics_daemon exited before creating its socket (rc={daemon.returncode}): {err.decode(errors='replace')}")
            try:
                if stat.S_ISSOCK(os.stat(unix_path).st_mode):
                    break
            except FileNotFoundError:
                pass
            time.sleep(0.05)
        else:
            pytest.fail(f"metrics_daemon did not create UNIX socket {unix_path}")

        forwarder = subprocess.Popen(
            ["socat", "TCP4-LISTEN:9999,bind=127.0.0.1,reuseaddr", f"UNIX-CONNECT:{unix_path}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        client = None
        deadline = time.time() + 4
        while time.time() < deadline:
            if forwarder.poll() is not None:
                _, err = forwarder.communicate()
                pytest.fail(f"socat forwarding process failed to listen on TCP port 9999: {err.decode(errors='replace')}")
            try:
                client = socket.create_connection(("127.0.0.1", 9999), timeout=0.5)
                break
            except OSError:
                time.sleep(0.05)
        assert client is not None, "Could not connect to TCP port 9999"

        with client:
            client.sendall((payload + "\n").encode())
            client.shutdown(socket.SHUT_WR)

        daemon.wait(timeout=4)
        assert daemon.returncode == 0, f"metrics_daemon exited with status {daemon.returncode}"
        forwarder.wait(timeout=4)
        assert forwarder.returncode == 0, f"socat forwarding process exited with status {forwarder.returncode}"

        deadline = time.time() + 4
        appended = b""
        while time.time() < deadline:
            if os.path.exists(log_path):
                with open(log_path, "rb") as f:
                    current = f.read()
                if current.startswith(before):
                    appended = current[len(before):]
                if payload.encode() in appended:
                    break
            time.sleep(0.05)

        assert payload.encode() in appended, (
            "The fresh verifier payload was not appended to app_metrics.log after being sent "
            "through TCP port 9999 to the daemon's UNIX socket."
        )
    finally:
        for proc in (forwarder, daemon):
            if proc is not None and proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=2)
        try:
            os.unlink(unix_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
