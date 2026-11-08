#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import socket
import subprocess
import threading
import time

import pytest


def terminate_process(proc):
    if proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)


def recv_exact(sock, size):
    chunks = []
    remaining = size
    while remaining:
        chunk = sock.recv(remaining)
        if not chunk:
            raise AssertionError(f"Connection closed with {remaining} bytes still expected")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def test_admin_users_txt():
    path = "/home/user/admin_users.txt"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["alice", "bob", "charlie"]
    assert lines == expected, f"Contents of {path} are incorrect. Expected {expected}, got {lines}"


def test_port_forward_exists():
    path = "/home/user/port_forward.py"
    assert os.path.isfile(path), f"File {path} does not exist."


def test_automate_exp_exists_and_executable():
    path = "/home/user/automate.exp"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_integration_port_forward_and_expect():
    legacy_service_path = "/home/user/legacy_service.py"
    port_forward_path = "/home/user/port_forward.py"
    automate_exp_path = "/home/user/automate.exp"

    legacy_proc = subprocess.Popen(
        [legacy_service_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    port_forward_proc = subprocess.Popen(
        ["python3", port_forward_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )

    time.sleep(1)

    try:
        expect_proc = subprocess.run(
            [automate_exp_path], capture_output=True, text=True, timeout=5
        )
        assert expect_proc.returncode == 0, (
            f"Expect script failed with return code {expect_proc.returncode}. "
            f"stdout: {expect_proc.stdout}, stderr: {expect_proc.stderr}"
        )
        assert "Access Granted" in expect_proc.stdout, (
            "The Expect run did not show the service's Access Granted response. "
            f"stdout: {expect_proc.stdout!r}, stderr: {expect_proc.stderr!r}"
        )
        legacy_proc.wait(timeout=2)
        assert legacy_proc.returncode == 0, "The legacy service did not complete successfully"
    except subprocess.TimeoutExpired:
        pytest.fail("Expect script timed out. It might be hanging waiting for input or output.")
    finally:
        terminate_process(legacy_proc)
        terminate_process(port_forward_proc)


def test_port_forward_carries_arbitrary_bidirectional_bytes():
    port_forward_path = "/home/user/port_forward.py"
    server_to_client = secrets.token_bytes(173)
    client_to_server = secrets.token_bytes(211)
    final_reply = secrets.token_bytes(137)
    backend_errors = []
    listening = threading.Event()

    def backend():
        listener = None
        conn = None
        try:
            listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind(("127.0.0.1", 8888))
            listener.listen(1)
            listener.settimeout(5)
            listening.set()
            conn, _ = listener.accept()
            conn.settimeout(5)
            conn.sendall(server_to_client)
            received = recv_exact(conn, len(client_to_server))
            assert received == client_to_server
            conn.sendall(final_reply)
        except BaseException as exc:
            backend_errors.append(exc)
            listening.set()
        finally:
            if conn is not None:
                conn.close()
            if listener is not None:
                listener.close()

    thread = threading.Thread(target=backend, daemon=True)
    thread.start()
    assert listening.wait(2), "Backend did not start"
    assert not backend_errors, f"Backend failed to start: {backend_errors}"

    forward_proc = subprocess.Popen(
        ["python3", port_forward_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    client.settimeout(5)
    try:
        deadline = time.monotonic() + 3
        while True:
            try:
                client.connect(("127.0.0.1", 9999))
                break
            except ConnectionRefusedError:
                if forward_proc.poll() is not None or time.monotonic() >= deadline:
                    stderr = forward_proc.stderr.read().decode(errors="replace")
                    pytest.fail(f"Port forwarder did not listen on 127.0.0.1:9999: {stderr}")
                time.sleep(0.05)

        assert recv_exact(client, len(server_to_client)) == server_to_client
        client.sendall(client_to_server)
        assert recv_exact(client, len(final_reply)) == final_reply
        thread.join(timeout=5)
        assert not thread.is_alive(), "Backend did not finish through the proxy"
        assert not backend_errors, f"Bidirectional forwarding failed: {backend_errors}"
    finally:
        client.close()
        terminate_process(forward_proc)


def test_expect_script_invokes_nc_and_performs_dialogue(tmp_path):
    automate_exp_path = "/home/user/automate.exp"
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    log_path = tmp_path / "nc-dialogue.json"
    fake_nc = fake_bin / "nc"
    fake_nc.write_text(
        """#!/usr/bin/env python3
import json
import os
import sys
import time

record = {"argv": sys.argv[1:]}
os.write(1, b"Username: ")
record["username"] = sys.stdin.buffer.readline().strip().decode("utf-8", "replace")
os.write(1, b"Password: ")
record["password"] = sys.stdin.buffer.readline().strip().decode("utf-8", "replace")
# A script which exits immediately after sending credentials will close this PTY
# before the delayed success response can be delivered.
time.sleep(0.8)
os.write(1, b"Access Granted\\n")
with open(os.environ["VERIFIER_NC_LOG"], "w") as f:
    json.dump(record, f)
"""
    )
    fake_nc.chmod(0o755)

    env = os.environ.copy()
    env["PATH"] = str(fake_bin) + os.pathsep + env.get("PATH", "")
    env["VERIFIER_NC_LOG"] = str(log_path)
    started = time.monotonic()
    try:
        result = subprocess.run(
            [automate_exp_path], capture_output=True, text=True, env=env, timeout=5
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Expect script timed out during the controlled dialogue")
    elapsed = time.monotonic() - started

    assert result.returncode == 0, (
        f"Expect script failed controlled dialogue. stdout: {result.stdout!r}, "
        f"stderr: {result.stderr!r}"
    )
    assert log_path.is_file(), "The Expect script did not run nc through PATH and complete its dialogue"
    with open(log_path) as f:
        record = json.load(f)
    assert record["argv"] == ["127.0.0.1", "9999"], (
        f"nc was invoked with incorrect arguments: {record['argv']}"
    )
    assert record["username"] == "admin", f"Incorrect username sent: {record['username']!r}"
    assert record["password"] == "supersecret", f"Incorrect password sent: {record['password']!r}"
    assert elapsed >= 0.7, "Expect script exited before the delayed Access Granted response"
    assert "Access Granted" in result.stdout, "Expect script did not receive the Access Granted response"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
