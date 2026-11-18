#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request
import pytest

RESTORE = "/home/user/restore"
SOURCE = f"{RESTORE}/health_monitor.c"
DAEMON = f"{RESTORE}/monitor_daemon"
REPORT = "/home/user/health_report.log"
EXPECTED_HEALTHY = "SYSTEM_HEALTHY: Service reachable at 127.0.0.1:9090"
EXPECTED_ALERT = "SYSTEM_ALERT: Service unreachable at 127.0.0.1:9090"


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def kill_listeners(port):
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listener_pids(port) and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_pids(port) and time.time() < deadline:
        time.sleep(0.05)
    assert not listener_pids(port), f"Could not release port {port}"


def wait_for_port(port, timeout=3):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.15):
                return
        except OSError:
            time.sleep(0.05)
    raise AssertionError(f"Port {port} did not become reachable")


def request_status():
    req = urllib.request.Request("http://127.0.0.1:8080/status")
    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            return response.status, response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8")


def start_probe_service():
    code = r'''
import socket
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 9090))
s.listen(16)
while True:
    c, _ = s.accept()
    c.close()
'''
    process = subprocess.Popen(["python3", "-c", code], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_for_port(9090)
    return process


def stop_process(process):
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=2)


def test_health_monitor_c_updated():
    assert os.path.isfile(SOURCE), f"File missing: {SOURCE}"
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "127.0.0.1" in content, "health_monitor.c does not contain the updated IP address '127.0.0.1'"
    assert "192.0.2.100" not in content, "health_monitor.c still contains the old IP address '192.0.2.100'"


def test_monitor_daemon_compiled():
    assert os.path.isfile(DAEMON), f"Compiled executable missing: {DAEMON}"
    assert os.access(DAEMON, os.X_OK), f"File is not executable: {DAEMON}"
    with open(DAEMON, "rb") as f:
        assert f.read(4) == b"\x7fELF", "monitor_daemon is not a compiled ELF executable"
    result = subprocess.run(
        ["gcc", "-fsyntax-only", SOURCE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"health_monitor.c is not valid compilable C:\n{result.stderr}"


def test_health_report_log_exists_and_correct():
    assert os.path.isfile(REPORT), f"Output log file missing: {REPORT}"
    with open(REPORT, "r") as f:
        content = f.read().strip()
    assert EXPECTED_HEALTHY in content, f"Log file content is incorrect. Expected to find '{EXPECTED_HEALTHY}', but got '{content}'"
    with open(REPORT, "rb") as f:
        assert f.read() == (EXPECTED_HEALTHY + "\n").encode(), "health_report.log is not the exact curl response"


def test_daemon_running_and_reachable():
    try:
        req = urllib.request.Request("http://127.0.0.1:8080/status")
        with urllib.request.urlopen(req, timeout=2) as response:
            body = response.read().decode("utf-8")
            assert EXPECTED_HEALTHY in body, "Daemon is running but returned unexpected content"
    except Exception as e:
        pytest.fail(f"Could not reach the monitor daemon on 127.0.0.1:8080. Is it running? Error: {e}")


def test_submitted_elf_actually_checks_backup_service():
    # Replace the agent-started process with the submitted artifact under the
    # required environment, then vary service availability in a shuffled order.
    kill_listeners(8080)
    kill_listeners(9090)
    try:
        os.remove(f"{RESTORE}/alert.log")
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env["HEALTH_PORT"] = "8080"
    env["ALERT_SCRIPT"] = f"{RESTORE}/send_alert.sh"
    daemon = subprocess.Popen([DAEMON], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    backend = None
    try:
        wait_for_port(8080)
        states = [True, False, True, False]
        random.SystemRandom().shuffle(states)
        for online in states:
            if online:
                if backend is None:
                    backend = start_probe_service()
                status, body = request_status()
                assert status == 200
                assert EXPECTED_HEALTHY in body
            else:
                stop_process(backend)
                backend = None
                kill_listeners(9090)
                status, body = request_status()
                assert status == 503
                assert EXPECTED_ALERT in body
                assert os.path.isfile(f"{RESTORE}/alert.log"), "Configured alert script was not invoked"
            assert daemon.poll() is None, "monitor_daemon exited while being exercised"
    finally:
        stop_process(backend)
        stop_process(daemon)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
