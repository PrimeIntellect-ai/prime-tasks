#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import secrets
import threading
from collections import Counter
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest
import requests

PROXY_PORT = 8080
APP_1_PORT = 8081
APP_2_PORT = 8082
MONITOR_PORT = 9090
AUTH_TOKEN = "SecretMonitor77"
THRESHOLD = 4
LOG_PATH = "/home/user/active_logs/proxy_access.log"

RANDOM_PATH_1 = "/dynamic/" + secrets.token_urlsafe(12) + "/nested"
RANDOM_PATH_2 = "/lookup/" + secrets.token_urlsafe(12)
RANDOM_BODY_1 = "backend-one-" + secrets.token_hex(24)
RANDOM_BODY_2 = "backend-two-" + secrets.token_hex(24)
DYNAMIC_RESPONSES = {
    (APP_1_PORT, RANDOM_PATH_1): (201, RANDOM_BODY_1),
    (APP_2_PORT, RANDOM_PATH_2): (418, RANDOM_BODY_2),
}
STATUS_RE = re.compile(r"(?<!\d)([1-5]\d{2})(?!\d)")


class MockBackendHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        dynamic = DYNAMIC_RESPONSES.get((self.server.server_port, self.path))
        if dynamic is not None:
            status, body = dynamic
            self.send_response(status)
            self.end_headers()
            self.wfile.write(body.encode())
        elif self.path == "/fail":
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"Error")
        else:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(
                f"Success from {self.server.server_port} for {self.path}".encode()
            )

    def log_message(self, format, *args):
        pass


def run_mock_server(port):
    server = HTTPServer(("127.0.0.1", port), MockBackendHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


@pytest.fixture(scope="module", autouse=True)
def setup_mock_backends():
    server1 = run_mock_server(APP_1_PORT)
    server2 = run_mock_server(APP_2_PORT)
    time.sleep(1)
    yield
    server1.shutdown()
    server2.shutdown()


def authenticated_health():
    return requests.get(
        f"http://127.0.0.1:{MONITOR_PORT}/health",
        headers={"Authorization": f"Bearer {AUTH_TOKEN}"},
        timeout=5,
    )


def read_log_lines():
    try:
        with open(LOG_PATH, "r", encoding="utf-8", errors="replace") as f:
            return [line.rstrip("\n") for line in f if line.strip()]
    except FileNotFoundError:
        return []


def wait_for_logged_statuses(expected, timeout=5):
    deadline = time.time() + timeout
    last_lines = []
    while time.time() < deadline:
        last_lines = read_log_lines()
        found = Counter()
        for line in last_lines:
            match = STATUS_RE.search(line)
            if match:
                found[int(match.group(1))] += 1
        if all(found[status] >= count for status, count in expected.items()):
            return last_lines
        time.sleep(0.1)
    pytest.fail(f"Expected logged statuses {dict(expected)}, got lines: {last_lines}")


def write_synthetic_log(error_count):
    with open(LOG_PATH, "w", encoding="utf-8") as f:
        f.write("GET /synthetic-ok HTTP/1.1 200\n")
        for i in range(error_count):
            f.write(f"GET /synthetic-{i} HTTP/1.1 500\n")
        f.flush()
        os.fsync(f.fileno())


def assert_health(resp, expected_code, expected_status):
    assert resp.status_code == expected_code, (
        f"Expected {expected_code} for {expected_status} state, got {resp.status_code}"
    )
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Monitoring API did not return valid JSON: {resp.text}")
    assert data.get("alert_status") == expected_status, (
        f"Expected alert_status {expected_status}, got {data}"
    )


def test_01_directories_and_symlink():
    assert os.path.isdir("/home/user/telemetry/logs/"), (
        "Directory /home/user/telemetry/logs/ does not exist."
    )
    assert os.path.isdir("/home/user/telemetry/config/"), (
        "Directory /home/user/telemetry/config/ does not exist."
    )
    assert os.path.islink("/home/user/active_logs"), (
        "Symlink /home/user/active_logs does not exist."
    )
    assert os.readlink("/home/user/active_logs") == "/home/user/telemetry/logs/", (
        "Symlink /home/user/active_logs does not point to /home/user/telemetry/logs/."
    )


def test_02_proxy_routing_and_logging():
    with open(LOG_PATH, "w", encoding="utf-8"):
        pass

    try:
        resp1 = requests.get(
            f"http://127.0.0.1:{PROXY_PORT}/app1/testdata", timeout=5
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to proxy on port {PROXY_PORT}: {e}")
    assert resp1.status_code == 200, (
        f"Expected 200 from proxy app1, got {resp1.status_code}"
    )
    assert "Success from 8081 for /testdata" in resp1.text, (
        f"Unexpected response from app1 proxy: {resp1.text}"
    )

    try:
        resp2 = requests.get(
            f"http://127.0.0.1:{PROXY_PORT}/app2/info", timeout=5
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to proxy on port {PROXY_PORT}: {e}")
    assert resp2.status_code == 200, (
        f"Expected 200 from proxy app2, got {resp2.status_code}"
    )
    assert "Success from 8082 for /info" in resp2.text, (
        f"Unexpected response from app2 proxy: {resp2.text}"
    )

    dynamic1 = requests.get(
        f"http://127.0.0.1:{PROXY_PORT}/app1{RANDOM_PATH_1}", timeout=5
    )
    assert dynamic1.status_code == 201, (
        f"Expected dynamic app1 status 201, got {dynamic1.status_code}"
    )
    assert dynamic1.text == RANDOM_BODY_1, (
        "Proxy did not return the runtime-generated app1 backend response"
    )

    dynamic2 = requests.get(
        f"http://127.0.0.1:{PROXY_PORT}/app2{RANDOM_PATH_2}", timeout=5
    )
    assert dynamic2.status_code == 418, (
        f"Expected dynamic app2 status 418, got {dynamic2.status_code}"
    )
    assert dynamic2.text == RANDOM_BODY_2, (
        "Proxy did not return the runtime-generated app2 backend response"
    )

    lines = wait_for_logged_statuses(Counter({200: 2, 201: 1, 418: 1}))
    assert len(lines) >= 4, "proxy_access.log does not contain one line per request"
    for line in lines:
        assert STATUS_RE.search(line), f"Log line has no parseable HTTP status: {line!r}"


def test_03_monitoring_api_and_log_reading():
    with open(LOG_PATH, "w", encoding="utf-8"):
        pass

    try:
        resp = requests.get(
            f"http://127.0.0.1:{MONITOR_PORT}/health", timeout=5
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to monitoring API on port {MONITOR_PORT}: {e}")
    assert resp.status_code == 401, (
        f"Expected 401 for no auth, got {resp.status_code}"
    )

    resp = requests.get(
        f"http://127.0.0.1:{MONITOR_PORT}/health",
        headers={"Authorization": "Bearer WrongToken"},
        timeout=5,
    )
    assert resp.status_code == 401, (
        f"Expected 401 for wrong auth, got {resp.status_code}"
    )

    assert_health(authenticated_health(), 200, "OK")

    for _ in range(5):
        failed = requests.get(
            f"http://127.0.0.1:{PROXY_PORT}/app1/fail", timeout=5
        )
        assert failed.status_code == 500, (
            f"Expected proxied backend failure status 500, got {failed.status_code}"
        )

    wait_for_logged_statuses(Counter({500: 5}))
    assert_health(authenticated_health(), 503, "CRITICAL")

    # Prove that /health derives its state from the specified log rather than
    # from a hardcoded request counter or sequence.
    write_synthetic_log(THRESHOLD)
    assert_health(authenticated_health(), 200, "OK")

    write_synthetic_log(THRESHOLD + 1)
    assert_health(authenticated_health(), 503, "CRITICAL")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
