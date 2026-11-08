#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import secrets
import stat
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

SCRIPT_PATH = "/home/user/uptime_monitor.py"
LOG_PATH = "/home/user/service_status.log"
EXPECTED_UID = pwd.getpwnam("user").pw_uid


def test_script_permissions():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert stat.S_ISREG(st.st_mode), f"Expected {SCRIPT_PATH} to be a regular file."
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o700, f"Expected {SCRIPT_PATH} to have permissions 0700, but got {oct(permissions)}"
    assert st.st_uid == EXPECTED_UID, f"Expected {SCRIPT_PATH} to be owned by user."


def test_log_permissions():
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} does not exist."
    st = os.stat(LOG_PATH)
    assert stat.S_ISREG(st.st_mode), f"Expected {LOG_PATH} to be a regular file."
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o600, f"Expected {LOG_PATH} to have permissions 0600, but got {oct(permissions)}"
    assert st.st_uid == EXPECTED_UID, f"Expected {LOG_PATH} to be owned by user."


def test_cron_job():
    try:
        crontab_output = subprocess.check_output(
            ["crontab", "-l"], stderr=subprocess.STDOUT
        ).decode("utf-8")
    except subprocess.CalledProcessError:
        crontab_output = ""

    found = False
    for raw_line in crontab_output.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if parts == ["*", "*", "*", "*", "*", SCRIPT_PATH]:
            found = True
            break

    assert found, "Exact every-minute cron command /home/user/uptime_monitor.py with no arguments was not found."


def run_and_check(expected_line):
    with open(LOG_PATH, "rb") as f:
        before = f.read()

    result = subprocess.run([SCRIPT_PATH], timeout=15, check=False)
    assert result.returncode == 0, f"Monitor exited with status {result.returncode}."

    with open(LOG_PATH, "rb") as f:
        after = f.read()

    assert after.startswith(before), "The monitor replaced or modified existing log content."
    appended = after[len(before):]
    expected = (expected_line + "\n").encode("utf-8")
    assert appended == expected, f"Expected exactly {expected!r} to be appended, got {appended!r}"


class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True


def handler_for(status_code, requests_seen):
    class HealthHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests_seen.append((self.command, self.path))
            self.send_response(status_code if self.path == "/health" else 404)
            self.end_headers()
            self.wfile.write(b"OK")

        def log_message(self, format, *args):
            pass

    return HealthHandler


def run_reachable_case(status_code, expected_line):
    requests_seen = []
    server = ReusableHTTPServer(
        ("localhost", 8080), handler_for(status_code, requests_seen)
    )
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    try:
        time.sleep(0.1)
        run_and_check(expected_line)
        assert ("GET", "/health") in requests_seen, "Monitor did not perform an HTTP GET on /health."
    finally:
        server.shutdown()
        server.server_close()
        server_thread.join()


def test_script_functionality_in_unpredictable_order():
    # The order is chosen only after the agent has finished, preventing a script
    # from passing by emitting a fixed sequence based on invocation count.
    cases = ["down", "up", "non200", "down", "up"]
    secrets.SystemRandom().shuffle(cases)

    for case in cases:
        if case == "down":
            run_and_check("STATUS: DOWN")
        elif case == "up":
            run_reachable_case(200, "STATUS: UP")
        else:
            run_reachable_case(503, "STATUS: DOWN")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
