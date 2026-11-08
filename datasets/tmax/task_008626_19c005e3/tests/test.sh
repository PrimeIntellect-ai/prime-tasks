#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import subprocess
import time
import urllib.request
import pytest


def listener_pids():
    result = subprocess.run(
        ["lsof", "-t", "-nP", "-iTCP:8081", "-sTCP:LISTEN"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    return {int(line) for line in result.stdout.splitlines() if line.strip().isdigit()}


def run_monitor():
    return subprocess.run(
        ["runuser", "-u", "user", "--", "/home/user/app/monitor.sh"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )


def test_nginx_config():
    conf_path = "/home/user/nginx.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} is missing"

    with open(conf_path, "r") as f:
        content = f.read()

    assert "proxy_pass http://127.0.0.1:8081" in content or "proxy_pass http://localhost:8081" in content, \
        "nginx.conf does not proxy to port 8081"


def test_nginx_running():
    pid_path = "/home/user/nginx.pid"
    assert os.path.isfile(pid_path), f"Nginx pid file {pid_path} is missing, Nginx might not be running"

    with open(pid_path, "r") as f:
        pid = f.read().strip()

    assert pid.isdigit(), f"Invalid PID in {pid_path}"

    try:
        os.kill(int(pid), 0)
    except OSError:
        pytest.fail(f"Nginx process with PID {pid} is not running")


def test_monitor_script():
    script_path = "/home/user/app/monitor.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable"

    with open(script_path, "r") as f:
        content = f.read()

    assert "server.py" in content, "monitor.sh does not reference server.py"
    assert "server.log" in content, "monitor.sh does not redirect to server.log"


def test_monitor_restarts_redirects_and_is_idempotent():
    # Stop the backend that the agent left running, then require monitor.sh itself
    # to restore the service.
    old_pids = listener_pids()
    for pid in old_pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    deadline = time.time() + 4
    while listener_pids() and time.time() < deadline:
        time.sleep(0.1)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    deadline = time.time() + 3
    while listener_pids() and time.time() < deadline:
        time.sleep(0.1)
    assert not listener_pids(), "Could not stop the existing backend before testing monitor.sh"

    log_path = "/home/user/app/server.log"
    try:
        os.remove(log_path)
    except FileNotFoundError:
        pass

    first = run_monitor()
    assert first.returncode == 0, f"monitor.sh failed to run as user: {first.stderr}"

    deadline = time.time() + 10
    pids = listener_pids()
    while not pids and time.time() < deadline:
        time.sleep(0.1)
        pids = listener_pids()

    assert len(pids) == 1, "monitor.sh did not start exactly one backend listener on port 8081"
    backend_pid = next(iter(pids))

    with open(f"/proc/{backend_pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\x00", b" ").decode("utf-8", errors="replace")
    assert "/home/user/app/server.py" in cmdline, "The listener started by monitor.sh is not server.py"

    assert os.path.isfile(log_path), "monitor.sh did not create server.log"
    log_stat = os.stat(log_path)
    stdout_stat = os.stat(f"/proc/{backend_pid}/fd/1")
    stderr_stat = os.stat(f"/proc/{backend_pid}/fd/2")
    assert (stdout_stat.st_dev, stdout_stat.st_ino) == (log_stat.st_dev, log_stat.st_ino), \
        "Backend standard output is not redirected to server.log"
    assert (stderr_stat.st_dev, stderr_stat.st_ino) == (log_stat.st_dev, log_stat.st_ino), \
        "Backend standard error is not redirected to server.log"

    with urllib.request.urlopen("http://127.0.0.1:8081/", timeout=2) as req:
        response = req.read().decode("utf-8")
    assert response == "Backend Service Operational\n", "Restarted backend returned an unexpected response"

    time.sleep(0.2)
    before = os.stat(log_path)
    before_state = (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)

    second = run_monitor()
    assert second.returncode == 0, f"Second monitor.sh invocation failed: {second.stderr}"
    time.sleep(0.5)

    assert listener_pids() == {backend_pid}, "monitor.sh is not idempotent; it changed or duplicated the backend"
    after = os.stat(log_path)
    after_state = (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
    assert after_state == before_state, "monitor.sh modified server.log despite the backend already running"


def test_success_txt():
    success_path = "/home/user/success.txt"
    assert os.path.isfile(success_path), f"File {success_path} is missing"

    with open(success_path, "r") as f:
        content = f.read()

    assert content == "Backend Service Operational\n", "success.txt does not contain the exact expected output"


def test_services_reachable():
    try:
        req = urllib.request.urlopen("http://127.0.0.1:8080/", timeout=2)
        response = req.read().decode("utf-8")
        assert response == "Backend Service Operational\n", "Nginx did not return the expected backend response"
    except Exception as e:
        pytest.fail(f"Failed to reach backend via Nginx on port 8080: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
