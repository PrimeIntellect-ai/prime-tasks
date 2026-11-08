#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import time
import subprocess
import urllib.request
import signal
import secrets


def test_nginx_conf_fixed():
    path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    assert "proxy_pass http://unix:/home/user/run/app.sock;" in content, \
        "The Nginx configuration does not point to the correct upstream socket path (/home/user/run/app.sock)."

    result = subprocess.run(
        ["nginx", "-t", "-c", path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert result.returncode == 0, f"The Nginx configuration is invalid: {result.stdout}"


def test_supervise_script_exists():
    path = "/home/user/supervise.sh"
    assert os.path.isfile(path), f"Supervisor script {path} is missing."
    result = subprocess.run(
        ["bash", "-n", path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert result.returncode == 0, f"Supervisor script is not valid Bash: {result.stdout}"


def test_nginx_serving_backend():
    try:
        req = urllib.request.Request("http://localhost:8080")
        with urllib.request.urlopen(req, timeout=5) as response:
            body = response.read().decode("utf-8")
            assert "Backend Alive" in body, "Nginx did not return the expected success message from the backend."
    except Exception as e:
        assert False, f"Failed to connect to Nginx on port 8080 or unexpected response: {e}"


def get_backend_pids():
    try:
        output = subprocess.check_output(["pgrep", "-f", "backend.py"]).decode("utf-8")
        return [int(pid) for pid in output.strip().split("\n") if pid]
    except subprocess.CalledProcessError:
        return []


def test_supervisor_restarts_backend_and_logs():
    pids = get_backend_pids()
    assert len(pids) > 0, "backend.py is not currently running."

    # Kill the backend processes
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    # Wait for supervisor to restart it
    time.sleep(3)

    new_pids = get_backend_pids()
    assert len(new_pids) > 0, "backend.py was not restarted by the supervisor after being killed."

    # Ensure it's a new process
    for pid in pids:
        assert pid not in new_pids, "backend.py has the same PID, it was not actually killed or restarted properly."

    # Check the log file
    log_path = "/home/user/supervise.log"
    assert os.path.isfile(log_path), f"Log file {log_path} was not created."

    with open(log_path, "r") as f:
        log_content = f.read()

    assert "[CRASH] restarted backend" in log_content, \
        f"The exact string '[CRASH] restarted backend' was not found in {log_path}."


def socket_owner_pids(socket_path):
    inodes = set()
    try:
        with open("/proc/net/unix", "r") as f:
            for line in f:
                fields = line.split()
                if len(fields) >= 8 and fields[7] == socket_path:
                    inodes.add(fields[6])
    except OSError:
        return set()

    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(entry))
                    break
        except OSError:
            continue
    return owners


def exact_backend_argv_pids():
    result = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            raw = open(f"/proc/{entry}/cmdline", "rb").read()
            argv = [part.decode(errors="replace") for part in raw.split(b"\0") if part]
            if "/home/user/backend.py" in argv:
                result.add(int(entry))
        except OSError:
            pass
    return result


def marker_count(path):
    try:
        with open(path, "r") as f:
            return sum(1 for line in f if line.rstrip("\n") == "[CRASH] restarted backend")
    except FileNotFoundError:
        return 0


def test_real_backend_is_restarted_and_nginx_proxies_to_its_socket():
    backend_path = "/home/user/backend.py"
    socket_path = "/home/user/run/app.sock"
    log_path = "/home/user/supervise.log"
    nonce = "backend-challenge-" + secrets.token_hex(24)
    launch_marker = "/tmp/backend-challenge-launch-" + secrets.token_hex(12)
    baseline_logs = marker_count(log_path)

    old_owners = socket_owner_pids(socket_path)
    kill_pids = old_owners | exact_backend_argv_pids()

    challenge = f'''#!/usr/bin/env python3
import os
import socket

socket_path = {socket_path!r}
marker_path = {launch_marker!r}
body = {nonce!r}.encode()
with open(marker_path, "w") as marker:
    marker.write(str(os.getpid()))
if os.path.exists(socket_path):
    os.remove(socket_path)
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(socket_path)
s.listen(8)
while True:
    conn, _ = s.accept()
    try:
        conn.recv(65536)
        response = (b"HTTP/1.1 200 OK\\r\\nContent-Type: text/plain\\r\\n" +
                    b"Content-Length: " + str(len(body)).encode() +
                    b"\\r\\nConnection: close\\r\\n\\r\\n" + body)
        conn.sendall(response)
    finally:
        conn.close()
'''
    temp_path = backend_path + ".verifier-new"
    with open(temp_path, "w") as f:
        f.write(challenge)
    os.chmod(temp_path, 0o755)
    os.replace(temp_path, backend_path)

    assert kill_pids, "No actual backend process was found to terminate."
    for pid in kill_pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    deadline = time.time() + 10
    launched_pid = None
    observed_body = None
    while time.time() < deadline:
        if os.path.isfile(launch_marker):
            try:
                with open(launch_marker, "r") as f:
                    launched_pid = int(f.read().strip())
            except (OSError, ValueError):
                launched_pid = None
        try:
            req = urllib.request.Request(
                "http://localhost:8080/?challenge=" + secrets.token_hex(4),
                headers={"Connection": "close"},
            )
            with urllib.request.urlopen(req, timeout=1) as response:
                observed_body = response.read().decode("utf-8")
        except Exception:
            observed_body = None

        if (launched_pid is not None and
                launched_pid in socket_owner_pids(socket_path) and
                observed_body == nonce and
                marker_count(log_path) > baseline_logs):
            break
        time.sleep(0.2)

    assert launched_pid is not None, \
        "The supervisor did not execute /home/user/backend.py after the backend was killed."
    assert launched_pid not in old_owners, "The backend was not replaced by a new process."
    assert launched_pid in socket_owner_pids(socket_path), \
        "The restarted /home/user/backend.py process does not own /home/user/run/app.sock."
    assert observed_body == nonce, \
        "Requests to port 8080 were not proxied to the restarted backend's Unix socket."
    assert marker_count(log_path) > baseline_logs, \
        "The supervisor did not append the exact restart log line after this verified crash."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
