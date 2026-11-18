#!/bin/bash
set -e
mkdir -p /logs/verifier

SCRIPT=/home/user/webhook.py
if [ ! -f "$SCRIPT" ] || [ -L "$SCRIPT" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'KILL_EOF' > /tmp/kill_port_8222.py
import os
import signal
import time

PORT = 8222
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                local_address = fields[1]
                state = fields[3]
                inode = fields[9]
                if int(local_address.rsplit(":", 1)[1], 16) == PORT and state == "0A":
                    inodes.add(inode)
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
                target = os.readlink(os.path.join(fd_dir, fd))
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pids.add(int(name))
                break
    except (FileNotFoundError, PermissionError):
        pass

for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass

time.sleep(0.3)
for pid in pids:
    try:
        os.kill(pid, 0)
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY

python3 /tmp/kill_port_8222.py
python3 "$SCRIPT" >/tmp/webhook-verifier.log 2>&1 &
SERVER_PID=$!
cleanup() {
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    python3 /tmp/kill_port_8222.py >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! python3 - << 'WAIT_EOF'
import socket
import time

for _ in range(40):
    try:
        with socket.create_connection(("127.0.0.1", 8222), timeout=0.2):
            raise SystemExit(0)
    except OSError:
        time.sleep(0.1)
raise SystemExit(1)
WAIT_EOF
then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import uuid

import pytest
import requests

PORT = 8222
TOKEN = "tr0ub4dour"
URL = f"http://127.0.0.1:{PORT}/alert"
LOG_DIR = "/home/user/alert_logs"
LOG_FILE = os.path.join(LOG_DIR, "alerts.txt")
BASELINE = b"verifier baseline\n"


def read_log():
    with open(LOG_FILE, "rb") as f:
        return f.read()


def test_webhook_contract_and_logging_side_effect():
    # Establish state that only a correctly authorized request should change.
    shutil.rmtree(LOG_DIR, ignore_errors=True)
    os.mkdir(LOG_DIR, 0o777)
    os.chmod(LOG_DIR, 0o777)
    with open(LOG_FILE, "wb") as f:
        f.write(BASELINE)

    try:
        response = requests.get(URL, timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to webhook server at {URL}. Is it running?")
    assert response.status_code == 401, f"Expected 401 Unauthorized with no token, got {response.status_code}"
    assert read_log() == BASELINE, "A request without Authorization modified the alert log"

    response = requests.get(URL, headers={"Authorization": "Bearer wrongtoken"}, timeout=2)
    assert response.status_code == 401, f"Expected 401 Unauthorized for bad token, got {response.status_code}"
    assert read_log() == BASELINE, "A request with an incorrect token modified the alert log"

    # Dynamically generated non-alert paths must not be accepted.
    for _ in range(2):
        other_url = f"http://127.0.0.1:{PORT}/not-alert-{uuid.uuid4().hex}"
        response = requests.get(other_url, headers={"Authorization": f"Bearer {TOKEN}"}, timeout=2)
        assert 400 <= response.status_code < 500, (
            f"Expected a client-error rejection for GET {other_url}, got {response.status_code}"
        )
        assert read_log() == BASELINE, "A request to a non-/alert path modified the alert log"

    # Only GET is accepted at /alert. BaseHTTPRequestHandler commonly uses 501
    # for methods for which no handler is implemented.
    for method in ("POST", "PUT", "PATCH", "DELETE"):
        response = requests.request(
            method, URL, headers={"Authorization": f"Bearer {TOKEN}"}, timeout=2
        )
        assert 400 <= response.status_code < 500 or response.status_code == 501, (
            f"Expected {method} /alert to be rejected, got {response.status_code}"
        )
        assert read_log() == BASELINE, f"{method} /alert modified the alert log"

    # The authorized request itself must cause the permission and append effects;
    # pre-created state cannot satisfy these checks.
    response = requests.get(URL, headers={"Authorization": f"Bearer {TOKEN}"}, timeout=2)
    assert response.status_code == 200, f"Expected 200 OK for valid token, got {response.status_code}"
    assert response.text.strip() == "Alert Logged", f"Expected body 'Alert Logged', got '{response.text}'"
    assert read_log() == BASELINE + b"Alert received\n", (
        "The authorized request did not append exactly one 'Alert received' line"
    )


def test_system_state_after_alert():
    assert os.path.exists(LOG_DIR), f"Directory {LOG_DIR} was not created."
    assert os.path.isdir(LOG_DIR), f"{LOG_DIR} is not a directory."

    dir_stat = os.stat(LOG_DIR)
    perms = stat.S_IMODE(dir_stat.st_mode)
    assert perms == 0o700, f"Expected permissions 700 for {LOG_DIR}, got {oct(perms)}"

    assert os.path.exists(LOG_FILE), f"Log file {LOG_FILE} was not created."
    assert os.path.isfile(LOG_FILE), f"{LOG_FILE} is not a file."

    with open(LOG_FILE, "r") as f:
        content = f.read()
    assert "Alert received" in content, f"Expected 'Alert received' in log file, got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
