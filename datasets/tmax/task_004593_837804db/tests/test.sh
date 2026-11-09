#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_health_monitor.py
import os
import signal
import subprocess
import sys
import tempfile
import time
import urllib.request

STATUS_LOG = "/home/user/health_logs/status.log"
ALERTS_LOG = "/home/user/health_logs/alerts.log"
SCRIPT = "/home/user/health_monitor.sh"
WATCHER_DIR = "/home/user/watcher_dir"
APP = "/home/user/app.py"
WATCHER = "/home/user/watcher.py"


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def process_pids(script_path):
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            cmdline = read_bytes(f"/proc/{name}/cmdline").split(b"\0")
            state = open(f"/proc/{name}/stat", "r").read().split()[2]
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        if state != "Z" and os.fsencode(script_path) in cmdline:
            found.append(int(name))
    return found


def http_status():
    with urllib.request.urlopen("http://localhost:8080/ping", timeout=2) as response:
        return response.status


def valid_status_lines(data):
    try:
        lines = data.decode("ascii").splitlines()
    except UnicodeDecodeError:
        return False
    return bool(lines) and all(len(line) == 3 and line.isdigit() and 100 <= int(line) <= 599 for line in lines)


def wait_for_status(expected, timeout=5):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            if http_status() == expected:
                return
        except Exception as exc:
            last_error = exc
        time.sleep(0.1)
    raise AssertionError(f"HTTP service did not return {expected}: {last_error}")


def save_path(path):
    if os.path.exists(path):
        return True, read_bytes(path)
    return False, b""


def restore_path(path, saved):
    existed, data = saved
    if existed:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
    elif os.path.exists(path):
        os.unlink(path)


# Retain the original final-state assertions.
assert os.path.isfile(STATUS_LOG), f"FAIL: {STATUS_LOG} not found in the correct directory."
status_content = read_bytes(STATUS_LOG)
assert b"200" in status_content, f"FAIL: '200' OK not found in {STATUS_LOG}."
assert len(status_content) > 0, f"FAIL: {STATUS_LOG} is empty."
assert os.path.isfile(ALERTS_LOG), f"FAIL: {ALERTS_LOG} not found."
alerts_content = read_bytes(ALERTS_LOG)
assert b"STORAGE_ALERT" in alerts_content, f"FAIL: 'STORAGE_ALERT' not found in {ALERTS_LOG}."

# Check the demanded artifact and the actual long-running services.
assert os.path.isfile(SCRIPT), f"FAIL: {SCRIPT} is missing."
assert os.access(SCRIPT, os.X_OK), f"FAIL: {SCRIPT} is not executable."
app_pids = process_pids(APP)
watcher_pids = process_pids(WATCHER)
assert app_pids, "FAIL: python3 /home/user/app.py is not running."
assert watcher_pids, "FAIL: python3 /home/user/watcher.py is not running."
assert http_status() == 200, "FAIL: the running /ping service does not return HTTP 200."
assert valid_status_lines(status_content), "FAIL: status.log is not composed of line-delimited valid HTTP status codes."
alert_lines = alerts_content.decode("utf-8").splitlines()
assert alert_lines and all(line == "STORAGE_ALERT" for line in alert_lines), "FAIL: alerts.log contains non-alert data or malformed alert lines."

# Prove the running watcher continues to invoke the monitor and append a real result.
before = read_bytes(STATUS_LOG)
deadline = time.time() + 5.5
new_data = b""
while time.time() < deadline:
    current = read_bytes(STATUS_LOG)
    if len(current) > len(before) and current.startswith(before):
        new_data = current[len(before):]
        if new_data.endswith(b"\n"):
            break
    time.sleep(0.2)
assert new_data, "FAIL: the running watcher did not append to status.log."
assert valid_status_lines(new_data), "FAIL: watcher output is not line-delimited HTTP status codes."
assert b"200\n" in new_data, "FAIL: watcher did not record the service's HTTP 200 response."

# Exercise the script under the watcher's stripped environment. A controlled service
# returns 204 so a script that merely writes the constant 200 cannot pass.
watched_paths = [STATUS_LOG, ALERTS_LOG,
                 os.path.join(WATCHER_DIR, "status.log"),
                 os.path.join(WATCHER_DIR, "alerts.log")]
saved = {path: save_path(path) for path in watched_paths}
stopped_watchers = []
test_server = None
killed_apps = []
try:
    for pid in process_pids(WATCHER):
        os.kill(pid, signal.SIGSTOP)
        stopped_watchers.append(pid)
    time.sleep(0.5)

    for pid in process_pids(APP):
        try:
            os.kill(pid, signal.SIGTERM)
            killed_apps.append(pid)
        except ProcessLookupError:
            pass
    deadline = time.time() + 4
    while time.time() < deadline and process_pids(APP):
        time.sleep(0.1)
    assert not process_pids(APP), "FAIL: could not isolate the HTTP probe for behavioral testing."

    server_source = r'''
from http.server import BaseHTTPRequestHandler, HTTPServer
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/ping":
            self.send_response(204)
            self.end_headers()
        else:
            self.send_response(418)
            self.end_headers()
    def log_message(self, *args):
        pass
HTTPServer(("localhost", 8080), Handler).serve_forever()
'''
    server_file = "/tmp/verifier_http_204.py"
    with open(server_file, "w") as f:
        f.write(server_source)
    test_server = subprocess.Popen([sys.executable, server_file], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_for_status(204)

    relative_before = {path: save_path(path) for path in watched_paths[2:]}
    expected = b"204\n"

    # After the append the file is exactly 100 bytes: strict >100 must not alert.
    with open(STATUS_LOG, "wb") as f:
        f.write(b"x" * (100 - len(expected)))
    if os.path.exists(ALERTS_LOG):
        os.unlink(ALERTS_LOG)
    result = subprocess.run(["/bin/bash", SCRIPT], cwd=WATCHER_DIR,
                            env={"PWD": WATCHER_DIR}, timeout=10,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert read_bytes(STATUS_LOG) == b"x" * (100 - len(expected)) + expected, \
        "FAIL: stripped-environment execution did not append the live HTTP 204 code to the absolute status log."
    assert not os.path.exists(ALERTS_LOG) or read_bytes(ALERTS_LOG) == b"", \
        "FAIL: STORAGE_ALERT was emitted when status.log was exactly 100 bytes."

    # After the append the file is 101 bytes: the alert must be appended now.
    with open(STATUS_LOG, "wb") as f:
        f.write(b"y" * (101 - len(expected)))
    if os.path.exists(ALERTS_LOG):
        os.unlink(ALERTS_LOG)
    result = subprocess.run(["/bin/bash", SCRIPT], cwd=WATCHER_DIR,
                            env={"PWD": WATCHER_DIR}, timeout=10,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert read_bytes(STATUS_LOG) == b"y" * (101 - len(expected)) + expected, \
        "FAIL: monitor did not append exactly one live HTTP status line to the absolute status log."
    assert os.path.isfile(ALERTS_LOG), "FAIL: alerts.log was not created above the 100-byte threshold."
    assert read_bytes(ALERTS_LOG).decode("utf-8").splitlines() == ["STORAGE_ALERT"], \
        "FAIL: monitor did not append the exact STORAGE_ALERT line above the threshold."

    for path, old_state in relative_before.items():
        assert save_path(path) == old_state, f"FAIL: monitor wrote to relative path {path}."
finally:
    if test_server is not None:
        test_server.terminate()
        try:
            test_server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            test_server.kill()
            test_server.wait()
    for path, state in saved.items():
        restore_path(path, state)
    if killed_apps:
        subprocess.Popen([sys.executable, APP], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
        wait_for_status(200)
    for pid in stopped_watchers:
        try:
            os.kill(pid, signal.SIGCONT)
        except ProcessLookupError:
            pass

assert process_pids(WATCHER), "FAIL: watcher is no longer running after verification."
assert process_pids(APP), "FAIL: app service is no longer running after verification."
PY_EOF

if python3 /tmp/verify_health_monitor.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
