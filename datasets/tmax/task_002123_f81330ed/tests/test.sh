#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import pwd
import re
import signal
import subprocess
import time
import urllib.request

import numpy as np
import pytest

HOME = "/home/user"
CONFIG = "/home/user/nginx/nginx.conf"
PIDFILE = "/home/user/nginx/nginx.pid"
EXPECTED_PORTS = {8001, 8002, 8003}


def run_as_user(argv):
    return subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user"] + argv,
        cwd=HOME,
        check=True,
        capture_output=True,
        text=True,
    )


def request(url):
    with urllib.request.urlopen(url, timeout=2) as response:
        body = response.read().decode("utf-8")
        assert response.status == 200
        return body


def read_pid():
    assert os.path.isfile(PIDFILE), f"Nginx PID file {PIDFILE} does not exist."
    with open(PIDFILE) as f:
        value = f.read().strip()
    assert value.isdigit(), f"Invalid Nginx PID file contents: {value!r}"
    return int(value)


def assert_user_nginx_process(pid):
    proc = f"/proc/{pid}"
    assert os.path.isdir(proc), f"Nginx PID {pid} is not running."
    exe = os.path.realpath(f"{proc}/exe")
    assert os.path.basename(exe) == "nginx", f"PID {pid} is not Nginx (executable {exe})."
    with open(f"{proc}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    assert CONFIG in cmdline, f"Nginx PID {pid} was not started with {CONFIG}: {cmdline!r}"
    with open(f"{proc}/status") as f:
        status = f.read()
    uid_line = next(line for line in status.splitlines() if line.startswith("Uid:"))
    real_uid = int(uid_line.split()[1])
    assert real_uid == pwd.getpwnam("user").pw_uid, "Nginx is not running as the user account."


def listener_pid(port):
    target_inode = None
    with open("/proc/net/tcp") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_address, state, inode = fields[1], fields[3], fields[9]
            address, hex_port = local_address.split(":")
            if address == "0100007F" and int(hex_port, 16) == port and state == "0A":
                target_inode = inode
                break
    assert target_inode is not None, f"Nothing is listening on 127.0.0.1:{port}."

    socket_name = f"socket:[{target_inode}]"
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") == socket_name:
                        return int(entry)
                except OSError:
                    pass
        except (OSError, PermissionError):
            pass
    pytest.fail(f"Could not identify the process listening on 127.0.0.1:{port}.")


def test_server_py_fixed():
    server_py_path = "/app/vendor/simple_service/server.py"
    assert os.path.isfile(server_py_path), f"File {server_py_path} does not exist."
    with open(server_py_path, "r") as f:
        content = f.read()
    assert "sys.argv[2]" not in content, "The deliberate bug (sys.argv[2]) is still present in server.py."


def test_required_artifacts_and_configuration():
    setup_script = "/home/user/setup_balancer.py"
    start_script = "/home/user/start_nginx.sh"
    assert os.path.isfile(setup_script), f"Required setup script {setup_script} does not exist."
    assert os.path.isfile(start_script), f"Required start script {start_script} does not exist."

    try:
        run_as_user(["python3", setup_script])
        assert os.path.isfile(CONFIG), f"Setup script did not generate {CONFIG}."
        with open(CONFIG, "rb") as f:
            first = f.read()
        run_as_user(["python3", setup_script])
        with open(CONFIG, "rb") as f:
            second = f.read()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"setup_balancer.py failed.\nStdout: {e.stdout}\nStderr: {e.stderr}")
    assert first == second, "setup_balancer.py is not idempotent; repeated execution changed nginx.conf."

    checked = subprocess.run(
        ["nginx", "-T", "-c", CONFIG, "-p", "/home/user/nginx/"],
        capture_output=True,
        text=True,
    )
    assert checked.returncode == 0, f"Generated Nginx configuration is invalid:\n{checked.stderr}"
    rendered = checked.stdout + "\n" + checked.stderr

    assert re.search(r"\blisten\s+127\.0\.0\.1:8080\s*;", rendered), "Nginx must listen on 127.0.0.1:8080."
    assert re.search(r"\bpid\s+/home/user/nginx/nginx\.pid\s*;", rendered), "Required Nginx PID path is not configured."
    assert re.search(r"\baccess_log\s+/home/user/nginx/access\.log(?:\s+[^;]+)?\s*;", rendered), "Required access log path is not configured."
    assert not re.search(r"\b(?:least_conn|ip_hash|random|hash)\b", rendered), "The upstream must use Nginx's default strict round-robin method."

    proxy_targets = re.findall(r"\bproxy_pass\s+http://([A-Za-z0-9_-]+)(?:/[^;]*)?\s*;", rendered)
    assert proxy_targets, "No HTTP proxy_pass to an upstream was found."
    valid_upstream = False
    for name in proxy_targets:
        match = re.search(r"\bupstream\s+" + re.escape(name) + r"\s*\{(.*?)\}", rendered, re.S)
        if not match:
            continue
        directives = re.findall(r"\bserver\s+([^;]+);", match.group(1))
        endpoints = []
        invalid_balance_option = False
        for directive in directives:
            parts = directive.split()
            endpoints.append(parts[0])
            if any(part == "backup" or part == "down" or (part.startswith("weight=") and part != "weight=1") for part in parts[1:]):
                invalid_balance_option = True
        if endpoints == ["127.0.0.1:8001", "127.0.0.1:8002", "127.0.0.1:8003"] and not invalid_balance_option:
            valid_upstream = True
            break
    assert valid_upstream, "The proxied upstream must contain exactly 127.0.0.1:8001, :8002, and :8003 in round-robin order."


def test_three_real_backends():
    pids = set()
    for port in sorted(EXPECTED_PORTS):
        body = request(f"http://127.0.0.1:{port}/")
        assert body.strip() == f"Served by {port}", f"Backend {port} returned {body!r}."
        pid = listener_pid(port)
        pids.add(pid)
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            args = [x.decode("utf-8", "replace") for x in f.read().split(b"\0") if x]
        assert "/app/vendor/simple_service/server.py" in args, f"Port {port} is not served by the required server.py: {args!r}"
        assert str(port) in args, f"Backend process for port {port} was not passed that port as its argument: {args!r}"
    assert len(pids) == 3, "The three backend ports must be served by three service instances."


def test_start_script_and_nginx_running():
    old_pid = read_pid()
    assert_user_nginx_process(old_pid)

    os.kill(old_pid, signal.SIGTERM)
    deadline = time.time() + 5
    while time.time() < deadline and os.path.exists(f"/proc/{old_pid}"):
        time.sleep(0.05)
    assert not os.path.exists(f"/proc/{old_pid}"), "Existing Nginx process did not stop for start-script verification."
    try:
        os.unlink(PIDFILE)
    except FileNotFoundError:
        pass

    try:
        run_as_user(["/bin/bash", "/home/user/start_nginx.sh"])
    except subprocess.CalledProcessError as e:
        pytest.fail(f"start_nginx.sh failed.\nStdout: {e.stdout}\nStderr: {e.stderr}")

    deadline = time.time() + 5
    last_error = None
    while time.time() < deadline:
        try:
            request("http://127.0.0.1:8080/")
            break
        except Exception as e:
            last_error = e
            time.sleep(0.1)
    else:
        pytest.fail(f"Failed to connect to Nginx on port 8080 after running start_nginx.sh: {last_error}")

    assert_user_nginx_process(read_pid())


def test_nginx_running():
    try:
        request("http://127.0.0.1:8080/")
    except Exception as e:
        pytest.fail(f"Failed to connect to Nginx on port 8080: {e}")


def test_load_balancer_distribution():
    counts = collections.defaultdict(int)
    for _ in range(300):
        try:
            body = request("http://127.0.0.1:8080/")
            port = int(body.strip().split()[-1])
            counts[port] += 1
        except Exception as e:
            pytest.fail(f"Request to load balancer failed: {e}")

    vals = list(counts.values())
    assert len(vals) == 3, f"Expected responses from 3 distinct backends, got {len(vals)}. Counts: {dict(counts)}"
    assert set(counts) == EXPECTED_PORTS, f"Expected backend ports 8001, 8002, and 8003, got {dict(counts)}"

    cv = np.std(vals) / np.mean(vals)
    assert cv <= 0.05, f"CV {cv:.4f} is greater than threshold 0.05. Traffic is not evenly balanced. Counts: {dict(counts)}"
    assert all(counts[port] == 100 for port in EXPECTED_PORTS), f"Strict round-robin did not produce 100 requests per backend: {dict(counts)}"


def test_log_rotation():
    log_path = "/home/user/nginx/access.log"
    rotated_log_path = "/home/user/nginx/access.log.1"
    rotate_script = "/home/user/rotate_logs.py"

    assert os.path.exists(rotate_script), f"Log rotation script {rotate_script} does not exist."
    assert os.path.exists(log_path), f"Nginx access log {log_path} does not exist."

    try:
        subprocess.run(["python3", rotate_script], check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Log rotation script failed with exit code {e.returncode}.\nStdout: {e.stdout}\nStderr: {e.stderr}")

    assert os.path.exists(rotated_log_path), f"Rotated log file {rotated_log_path} was not created."

    try:
        request("http://127.0.0.1:8080/")
    except Exception as e:
        pytest.fail(f"Request to load balancer failed after log rotation: {e}")

    time.sleep(0.5)
    assert os.path.exists(log_path), f"New log file {log_path} was not created by Nginx after rotation."
    assert os.path.getsize(log_path) > 0, f"New log file {log_path} is empty, Nginx might not have reopened its log files."
    assert_user_nginx_process(read_pid())
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
