#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import socket
import stat
import subprocess
import threading
import time
import uuid
import pytest

USER = pwd.getpwnam("user")

def run_as_user(cmd, timeout=20):
    def demote():
        os.setgroups([])
        os.setgid(USER.pw_gid)
        os.setuid(USER.pw_uid)

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    env["USER"] = "user"
    return subprocess.run(
        cmd,
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
        preexec_fn=demote,
    )

def directory_size(path):
    total = 0
    for root, dirs, files in os.walk(path):
        for name in files:
            total += os.path.getsize(os.path.join(root, name))
    return total

def test_dashboard_result():
    target_dir = "/home/user/target_logs"
    total_size = 0
    if os.path.exists(target_dir):
        for root, dirs, files in os.walk(target_dir):
            for f in files:
                total_size += os.path.getsize(os.path.join(root, f))
    else:
        pytest.fail(f"Target directory {target_dir} does not exist.")

    expected_content = f"Target: {target_dir}, Size: {total_size}"

    result_file = "/home/user/dashboard_result.txt"
    assert os.path.exists(result_file), f"{result_file} does not exist. The dashboard script must create this file."

    with open(result_file, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {result_file} is incorrect.\nExpected: '{expected_content}'\nGot: '{content}'"

def test_port_forwarding():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2.0)
    try:
        s.connect(("127.0.0.1", 9090))
        data = s.recv(1024).decode("utf-8")
        assert "Passcode:" in data, "Did not receive 'Passcode:' prompt from port 9090. Port forwarding might be misconfigured."

        s.sendall(b"obs_secure_123\n")
        data = s.recv(1024).decode("utf-8")
        assert "Action:" in data, "Did not receive 'Action:' prompt from port 9090 after sending passcode."

        s.sendall(b"CHECK_FS\n")
        data = s.recv(1024).decode("utf-8")
        assert "/home/user/target_logs" in data, "Did not receive correct directory path from port 9090 after sending CHECK_FS."
    except ConnectionRefusedError:
        pytest.fail("Connection refused on 127.0.0.1:9090. Port forwarding is not active.")
    except Exception as e:
        pytest.fail(f"Port forwarding on 9090 failed or daemon interaction failed: {e}")
    finally:
        s.close()

def test_scripts_exist():
    assert os.path.exists("/home/user/dashboard.py"), "/home/user/dashboard.py does not exist."
    assert os.path.exists("/home/user/health_check.py") or os.path.exists("/home/user/health_check.exp"), \
        "Neither /home/user/health_check.py nor /home/user/health_check.exp exists. The interactive automation script is missing."
    assert os.path.isfile("/home/user/dashboard.py"), "/home/user/dashboard.py is not a regular file."
    for path in ("/home/user/health_check.py", "/home/user/health_check.exp"):
        if os.path.exists(path):
            assert os.path.isfile(path), f"{path} is not a regular file."

def test_dynamic_forwarding_health_check_and_dashboard_execution():
    token = uuid.uuid4().hex
    daemon_target = f"/home/user/verifier_daemon_target_{token}"
    automation_target = f"/home/user/verifier_automation_target_{token}"

    for base, sizes in ((daemon_target, (1103, 2207)), (automation_target, (1731, 2849))):
        os.makedirs(os.path.join(base, "nested"), exist_ok=False)
        with open(os.path.join(base, "first.bin"), "wb") as f:
            f.write(os.urandom(sizes[0]))
        with open(os.path.join(base, "nested", "second.bin"), "wb") as f:
            f.write(os.urandom(sizes[1]))
        os.chmod(base, 0o777)
        os.chmod(os.path.join(base, "nested"), 0o777)
        os.chmod(os.path.join(base, "first.bin"), 0o666)
        os.chmod(os.path.join(base, "nested", "second.bin"), 0o666)

    socket_path = "/home/user/admin.sock"
    try:
        os.unlink(socket_path)
    except FileNotFoundError:
        pass

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(socket_path)
    os.chmod(socket_path, 0o777)
    server.listen(8)
    server.settimeout(0.25)
    stop = threading.Event()
    completed = []
    server_errors = []

    def receive_line(conn):
        data = b""
        while b"\n" not in data and len(data) < 4096:
            part = conn.recv(1024)
            if not part:
                break
            data += part
        return data.decode("utf-8", errors="replace").strip()

    def serve():
        try:
            while not stop.is_set():
                try:
                    conn, _ = server.accept()
                except socket.timeout:
                    continue
                with conn:
                    conn.settimeout(3)
                    conn.sendall(b"Passcode:")
                    if receive_line(conn) != "obs_secure_123":
                        continue
                    conn.sendall(b"Action:")
                    if receive_line(conn) != "CHECK_FS":
                        continue
                    conn.sendall((daemon_target + "\n").encode())
                    completed.append(True)
        except Exception as exc:
            if not stop.is_set():
                server_errors.append(repr(exc))

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    time.sleep(0.1)

    health_paths = [p for p in ("/home/user/health_check.py", "/home/user/health_check.exp") if os.path.isfile(p)]
    successful_health = False
    health_outputs = []
    for path in health_paths:
        command = ["python3", path] if path.endswith(".py") else ["expect", path]
        try:
            result = run_as_user(command, timeout=15)
            health_outputs.append(f"{path}: rc={result.returncode}, output={result.stdout!r}")
            if result.returncode == 0 and daemon_target in result.stdout:
                successful_health = True
                break
        except subprocess.TimeoutExpired:
            health_outputs.append(f"{path}: timed out")

    assert successful_health, (
        "No submitted health-check script successfully authenticated through TCP port 9090 "
        "and returned the verifier-selected path from /home/user/admin.sock. " + "; ".join(health_outputs)
    )
    assert completed, "The health check did not reach the replacement UNIX-socket daemon; port 9090 is not a real forward to /home/user/admin.sock."
    assert not server_errors, f"Replacement UNIX-socket daemon failed: {server_errors}"

    originals = {}
    result_file = "/home/user/dashboard_result.txt"
    try:
        # Replace the already-tested automation artifact temporarily with a dynamic
        # output provider. The dashboard must execute it and consume its output,
        # rather than independently connecting or using a hard-coded path.
        for path in health_paths:
            with open(path, "rb") as f:
                originals[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))
            if path.endswith(".py"):
                stub = f"#!/usr/bin/env python3\nprint({automation_target!r})\n"
            else:
                stub = f"#!/usr/bin/expect -f\nputs \"{automation_target}\"\n"
            with open(path, "w") as f:
                f.write(stub)
            os.chmod(path, originals[path][1])

        try:
            os.unlink(result_file)
        except FileNotFoundError:
            pass

        dashboard = run_as_user(["python3", "/home/user/dashboard.py"], timeout=20)
        assert dashboard.returncode == 0, f"dashboard.py failed when executed: {dashboard.stdout}"
        assert os.path.isfile(result_file), "Executing dashboard.py did not create /home/user/dashboard_result.txt."
        with open(result_file, "r") as f:
            actual = f.read().strip()
        expected = f"Target: {automation_target}, Size: {directory_size(automation_target)}"
        assert actual == expected, (
            "dashboard.py did not execute and consume the health-check automation output. "
            f"Expected {expected!r}, got {actual!r}. Dashboard output: {dashboard.stdout!r}"
        )
    finally:
        for path, (content, mode) in originals.items():
            with open(path, "wb") as f:
                f.write(content)
            os.chmod(path, mode)
        stop.set()
        server.close()
        thread.join(timeout=2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
