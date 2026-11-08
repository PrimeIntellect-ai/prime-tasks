#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import stat
import subprocess
import time
import uuid
import pytest

APP_PATH = "/home/user/app.py"
CONF_PATH = "/home/user/supervisord.conf"
PID_PATH = "/home/user/supervisord.pid"
SOCK_PATH = "/home/user/app.sock"
LOG_PATH = "/home/user/success.log"


def test_app_py_fixed():
    """Verify that app.py unlinks or removes the socket file."""
    assert os.path.isfile(APP_PATH), f"File {APP_PATH} is missing."
    with open(APP_PATH, "r") as f:
        content = f.read()

    assert "os.unlink(" in content or "os.remove(" in content, "app.py does not seem to unlink or remove the socket file before binding."
    assert 'os.environ.get("TZ") != "Europe/Berlin"' in content, "The timezone check in app.py was removed or altered."


def test_supervisord_conf_updated():
    """Verify supervisord.conf is updated with correct socket, timezone, and autorestart."""
    assert os.path.isfile(CONF_PATH), f"File {CONF_PATH} is missing."
    with open(CONF_PATH, "r") as f:
        content = f.read()

    assert "/home/user/app.sock" in content, "supervisord.conf command does not use /home/user/app.sock"
    assert "autorestart=true" in content.lower(), "supervisord.conf does not have autorestart=true"
    assert re.search(r'environment\s*=.*TZ=["\']?Europe/Berlin["\']?', content), "supervisord.conf does not set the environment variable TZ=Europe/Berlin correctly."


def test_supervisord_running():
    """Verify supervisord is running by checking the pidfile."""
    assert os.path.isfile(PID_PATH), f"supervisord pidfile {PID_PATH} is missing. Is supervisord running?"


def test_app_sock_exists():
    """Verify the unix socket exists and is a socket."""
    assert os.path.exists(SOCK_PATH), f"Socket {SOCK_PATH} does not exist."
    mode = os.stat(SOCK_PATH).st_mode
    assert stat.S_ISSOCK(mode), f"{SOCK_PATH} is not a socket."


def test_success_log():
    """Verify that the success log contains the expected response."""
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} is missing."
    with open(LOG_PATH, "r") as f:
        content = f.read()

    assert "HTTP/1.1 200 OK" in content or "Hello from Microservice" in content, "success.log does not contain the expected HTTP response."


def _cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def _stop_old_supervisors():
    victims = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        cmd = _cmdline(pid)
        if "supervisord" in cmd and CONF_PATH in cmd:
            victims.append(pid)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline and any(os.path.exists(f"/proc/{p}") for p in victims):
        time.sleep(0.1)
    for pid in victims:
        if os.path.exists(f"/proc/{pid}"):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def _read_pidfile():
    try:
        with open(PID_PATH) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None


def _direct_app_children(supervisor_pid):
    try:
        with open(f"/proc/{supervisor_pid}/task/{supervisor_pid}/children") as f:
            pids = [int(x) for x in f.read().split()]
    except OSError:
        return []
    result = []
    for pid in pids:
        cmd = _cmdline(pid)
        if APP_PATH in cmd and SOCK_PATH in cmd:
            try:
                with open(f"/proc/{pid}/stat") as f:
                    state = f.read().split()[2]
            except OSError:
                continue
            if state != "Z":
                result.append(pid)
    return result


def _wait_for_app(supervisor_pid, excluded=None, timeout=12):
    excluded = set(excluded or [])
    deadline = time.time() + timeout
    while time.time() < deadline:
        assert os.path.exists(f"/proc/{supervisor_pid}"), "The newly started supervisord process exited"
        candidates = [p for p in _direct_app_children(supervisor_pid) if p not in excluded]
        if candidates and os.path.exists(SOCK_PATH):
            try:
                if stat.S_ISSOCK(os.stat(SOCK_PATH).st_mode):
                    return candidates[0]
            except OSError:
                pass
        time.sleep(0.15)
    raise AssertionError("supervisord did not start the configured myapp process on /home/user/app.sock")


def _assert_child_environment(pid):
    with open(f"/proc/{pid}/environ", "rb") as f:
        env = f.read().split(b"\0")
    assert b"TZ=Europe/Berlin" in env, "The running myapp process did not receive TZ=Europe/Berlin"


def _assert_child_owns_path_socket(pid):
    socket_inodes = set()
    fd_dir = f"/proc/{pid}/fd"
    for fd in os.listdir(fd_dir):
        try:
            target = os.readlink(os.path.join(fd_dir, fd))
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            socket_inodes.add(match.group(1))

    matched = False
    with open("/proc/net/unix") as f:
        next(f, None)
        for line in f:
            fields = line.split()
            if len(fields) >= 8 and fields[-1] == SOCK_PATH and fields[-2] in socket_inodes:
                matched = True
                break
    assert matched, "The supervised myapp process does not own the configured Unix socket"


def _request_service():
    request_path = "/verify-" + uuid.uuid4().hex
    result = subprocess.run(
        ["/usr/bin/curl", "--silent", "--show-error", "--include", "--max-time", "5",
         "--unix-socket", SOCK_PATH, "http://localhost" + request_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    assert result.returncode == 0, f"HTTP request through the Unix socket failed: {result.stderr.decode(errors='replace')}"
    response = result.stdout
    assert response.startswith(b"HTTP/1.1 200 OK"), f"Service returned an invalid HTTP response: {response!r}"
    assert b"Hello from Microservice" in response, "The live service did not return the expected application response"


def test_live_supervisor_application_and_restart():
    """Exercise stale-socket cleanup, supervisor placement, HTTP serving, TZ, and autorestart."""
    _stop_old_supervisors()
    for path in (PID_PATH, SOCK_PATH):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    # Leave behind a genuine stale Unix socket. The configured application must
    # remove it before bind rather than merely relying on a clean verifier state.
    stale = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    stale.bind(SOCK_PATH)
    stale.close()
    assert stat.S_ISSOCK(os.stat(SOCK_PATH).st_mode)

    started = subprocess.run(
        ["/usr/bin/supervisord", "-c", CONF_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert started.returncode == 0, (
        "Starting supervisord with the submitted configuration failed: "
        + started.stdout.decode(errors="replace")
        + started.stderr.decode(errors="replace")
    )

    deadline = time.time() + 5
    supervisor_pid = None
    while time.time() < deadline:
        supervisor_pid = _read_pidfile()
        if supervisor_pid and os.path.exists(f"/proc/{supervisor_pid}"):
            break
        time.sleep(0.1)
    assert supervisor_pid and os.path.exists(f"/proc/{supervisor_pid}"), "The pidfile does not identify a live supervisord process"
    assert "supervisord" in _cmdline(supervisor_pid), "The pidfile does not belong to supervisord"

    child = _wait_for_app(supervisor_pid)
    _assert_child_environment(child)
    _assert_child_owns_path_socket(child)
    _request_service()

    # An unexpected crash must cause supervisor to launch a different app
    # process. The replacement also has to remove the socket left by SIGKILL.
    os.kill(child, signal.SIGKILL)
    replacement = _wait_for_app(supervisor_pid, excluded={child})
    assert replacement != child, "myapp was not automatically restarted after a crash"
    _assert_child_environment(replacement)
    _assert_child_owns_path_socket(replacement)
    _request_service()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
