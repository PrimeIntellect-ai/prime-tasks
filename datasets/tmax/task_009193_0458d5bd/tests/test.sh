#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import signal
import socket
import string
import subprocess
import time
import urllib.error
import urllib.request

import pytest

APP_DIR = "/home/user/app"
SUCCESS_LOG = os.path.join(APP_DIR, "success.log")
TEST_STACK_PY = os.path.join(APP_DIR, "test_stack.py")
NGINX_CONF = os.path.join(APP_DIR, "nginx.conf")
USER_UID = pwd.getpwnam("user").pw_uid


def proc_info():
    result = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace").strip()
            with open(f"/proc/{entry}/status") as f:
                status = f.read()
            uid = int(re.search(r"^Uid:\s+(\d+)", status, re.M).group(1))
            ppid = int(re.search(r"^PPid:\s+(\d+)", status, re.M).group(1))
            result[int(entry)] = {"cmdline": cmdline, "uid": uid, "ppid": ppid}
        except (FileNotFoundError, PermissionError, AttributeError):
            pass
    return result


def descendants(root_pid, processes):
    found = set()
    pending = [root_pid]
    while pending:
        parent = pending.pop()
        for pid, info in processes.items():
            if info["ppid"] == parent and pid not in found:
                found.add(pid)
                pending.append(pid)
    return found


def listening_inodes(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def process_owns_socket(pid, inodes):
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
            except (FileNotFoundError, PermissionError):
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in inodes:
                return True
    except (FileNotFoundError, PermissionError):
        pass
    return False


def get_url(url, timeout=5):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.getcode(), response.read().decode("utf-8")


def wait_for_url(url, expected=(200, "Backend Active"), timeout=10):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            value = get_url(url, timeout=1)
            if value == expected:
                return
            last_error = AssertionError(f"Unexpected response: {value!r}")
        except Exception as exc:
            last_error = exc
        time.sleep(0.2)
    raise AssertionError(f"Service did not become ready at {url}: {last_error}")


def proxy_target():
    rendered = subprocess.check_output(
        ["nginx", "-T", "-c", NGINX_CONF, "-g", "pid /home/user/app/nginx.pid;"],
        stderr=subprocess.STDOUT,
        text=True,
    )
    match = re.search(r"proxy_pass\s+http://(127\.0\.0\.1|localhost):(\d+)\s*;", rendered)
    assert match, "The active Nginx configuration must proxy to a local HTTP backend."
    assert not re.search(r"\breturn\s+200\b", rendered), "Nginx must not synthesize the successful response directly."
    assert "/home/user/app/access.log" in rendered
    assert "/home/user/app/error.log" in rendered
    return match.group(1), int(match.group(2))


def test_success_log_exists_and_content():
    assert os.path.isfile(SUCCESS_LOG), f"Log file {SUCCESS_LOG} is missing."
    with open(SUCCESS_LOG, "r") as f:
        content = f.read().strip()

    expected_log = "STATUS: 200, BODY: Backend Active"
    assert expected_log in content, f"Expected '{expected_log}' in {SUCCESS_LOG}, but found:\n{content}"


def test_test_stack_script_exists():
    assert os.path.isfile(TEST_STACK_PY), f"Test script {TEST_STACK_PY} is missing."


def test_nginx_and_backend_running():
    try:
        status, body = get_url("http://127.0.0.1:8080")
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx at http://127.0.0.1:8080: {e}")

    assert status == 200, f"Expected HTTP status 200, got {status}"
    assert body == "Backend Active", f"Expected body 'Backend Active', got '{body}'"


def test_processes_running():
    ps_output = subprocess.check_output(["ps", "aux"]).decode("utf-8")

    nginx_running = "nginx" in ps_output
    monitor_running = "monitor.py" in ps_output

    assert nginx_running, "Nginx process is not running."
    assert monitor_running, "monitor.py process is not running."

    processes = proc_info()
    nginx = [
        pid for pid, info in processes.items()
        if info["uid"] == USER_UID and "nginx" in info["cmdline"] and "-c /home/user/app/nginx.conf" in info["cmdline"]
    ]
    monitors = [
        pid for pid, info in processes.items()
        if info["uid"] == USER_UID and re.search(r"(^|\s)/home/user/app/monitor\.py($|\s)", info["cmdline"])
    ]
    assert nginx, "Nginx is not running as user with the provided configuration."
    assert monitors, "The real /home/user/app/monitor.py process is not running as user."


def test_proxy_depends_on_monitored_backend():
    host, port = proxy_target()
    status, body = get_url(f"http://{host}:{port}")
    assert status == 200
    assert body == "Backend Active"

    processes = proc_info()
    monitors = [
        pid for pid, info in processes.items()
        if info["uid"] == USER_UID and re.search(r"(^|\s)/home/user/app/monitor\.py($|\s)", info["cmdline"])
    ]
    assert monitors, "Monitor process is missing."
    children = set()
    for monitor_pid in monitors:
        children.update(descendants(monitor_pid, processes))

    inodes = listening_inodes(port)
    backend_pids = [pid for pid in children if process_owns_socket(pid, inodes)]
    assert backend_pids, "The backend listener is not a process managed by monitor.py."

    for pid in backend_pids:
        os.kill(pid, signal.SIGSTOP)
    try:
        try:
            result = get_url("http://127.0.0.1:8080", timeout=2)
        except Exception:
            result = None
        assert result != (200, "Backend Active"), "Nginx still serves success while the monitored backend is suspended."
    finally:
        for pid in backend_pids:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass

    wait_for_url("http://127.0.0.1:8080")


def test_test_stack_performs_request_and_appends_observed_result():
    before = open(SUCCESS_LOG, "rb").read()
    token = "DYNAMIC_" + "".join(random.choice(string.ascii_letters) for _ in range(24))
    mock_code = f'''\
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(201)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write({token!r}.encode())
    def log_message(self, *args):
        pass
HTTPServer(("127.0.0.1", 8080), H).handle_request()
'''

    stop_cmd = ["runuser", "-u", "user", "--", "nginx", "-c", NGINX_CONF,
                "-g", "pid /home/user/app/nginx.pid;", "-s", "quit"]
    start_cmd = ["runuser", "-u", "user", "--", "nginx", "-c", NGINX_CONF,
                 "-g", "pid /home/user/app/nginx.pid; daemon on;"]
    subprocess.run(stop_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)

    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                pass
        except OSError:
            break
        time.sleep(0.1)
    else:
        pytest.fail("Nginx did not release port 8080 for the test_stack.py behavioral test.")

    mock = subprocess.Popen(["python3", "-c", mock_code])
    try:
        time.sleep(0.3)
        completed = subprocess.run(
            ["runuser", "-u", "user", "--", "python3", TEST_STACK_PY],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert completed.returncode == 0, f"test_stack.py failed: {completed.stderr}"
        mock.wait(timeout=5)
    finally:
        if mock.poll() is None:
            mock.terminate()
            mock.wait(timeout=5)
        subprocess.run(start_cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)

    wait_for_url("http://127.0.0.1:8080")
    after = open(SUCCESS_LOG, "rb").read()
    assert after.startswith(before), "test_stack.py must append to success.log rather than replace it."
    appended = after[len(before):].decode("utf-8")
    expected = f"STATUS: 201, BODY: {token}"
    assert expected in appended, f"test_stack.py did not log the response it actually received; expected {expected!r}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
