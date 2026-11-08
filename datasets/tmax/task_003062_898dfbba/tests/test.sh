#!/bin/bash
mkdir -p /logs/verifier

APP_PID=""
MOCK_PID=""

cleanup() {
    if [ -n "$APP_PID" ]; then
        kill -- -"$APP_PID" 2>/dev/null || true
        kill "$APP_PID" 2>/dev/null || true
    fi
    if [ -n "$MOCK_PID" ]; then
        kill "$MOCK_PID" 2>/dev/null || true
    fi
    pkill -f '[p]ython.*\/home\/user\/app.py' 2>/dev/null || true
}
trap cleanup EXIT

wait_for_port() {
    python3 - <<'PY'
import socket
import time

for _ in range(100):
    try:
        with socket.create_connection(("127.0.0.1", 5000), timeout=0.1):
            raise SystemExit(0)
    except OSError:
        time.sleep(0.1)
raise SystemExit(1)
PY
}

run_verification() {
    # Preserve the original artifact assertions before attempting execution.
    [ -f /home/user/app.py ] || return 1
    [ -f /home/user/test_e2e.rb ] || return 1

    # Ensure the service under test is the submitted app.py, not a process left
    # listening on the required port.
    pkill -f '[p]ython.*\/home\/user\/app.py' 2>/dev/null || true
    sleep 0.3
    rm -f /home/user/integration_result.log

    setsid python3 /home/user/app.py >/tmp/submitted_app.log 2>&1 &
    APP_PID=$!
    wait_for_port || return 1
    kill -0 "$APP_PID" 2>/dev/null || return 1

    # Execute the submitted Ruby integration test against the submitted API.
    timeout 20 ruby /home/user/test_e2e.rb >/tmp/submitted_ruby.log 2>&1 || return 1

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import urllib.request


def post_graph(graph):
    request = urllib.request.Request(
        "http://127.0.0.1:5000/api/v1/compute",
        data=json.dumps(graph).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        assert response.status == 200
        return json.loads(response.read().decode("utf-8"))


def test_integration_result_log():
    log_path = "/home/user/integration_result.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing. Did the Ruby script run successfully?"

    with open(log_path, "r") as f:
        raw = f.read()
    content = raw.strip()

    expected = "Result: 73, Status: 200"
    assert expected in content, f"Log file {log_path} content does not match expected output. Expected to find '{expected}', but got '{content}'"
    assert raw in (expected, expected + "\n"), f"Log file must contain exactly '{expected}' (optionally followed by one newline), got {raw!r}"


def test_app_script_exists():
    app_path = "/home/user/app.py"
    assert os.path.isfile(app_path), f"Python API script {app_path} is missing."


def test_ruby_script_exists():
    ruby_path = "/home/user/test_e2e.rb"
    assert os.path.isfile(ruby_path), f"Ruby end-to-end test script {ruby_path} is missing."


def test_submitted_api_evaluates_derived_graphs():
    app_pid = int(os.environ["SUBMITTED_APP_PID"])
    os.kill(app_pid, 0)

    for _ in range(5):
        a = secrets.randbelow(31) - 15
        b = secrets.randbelow(19) - 9
        c = secrets.randbelow(17) - 8
        graph = {
            "nodes": {
                "A": {"type": "value", "value": a},
                "B": {"type": "value", "value": b},
                "C": {"type": "value", "value": c},
                "SUM": {"type": "add", "inputs": ["A", "B", "C"]},
                "PRODUCT": {"type": "mul", "inputs": ["SUM", "B", "A"]},
                "TARGET": {"type": "add", "inputs": ["PRODUCT", "C"]},
            },
            "target": "TARGET",
        }
        expected = ((a + b + c) * b * a) + c
        assert post_graph(graph) == {"result": expected}
TEST_EOF

    SUBMITTED_APP_PID="$APP_PID" python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    # Exercise the Ruby client independently. A mock server returns a fresh,
    # unpredictable result and records the request, proving that the script sent
    # the specified graph and used the HTTP response to produce its log.
    kill -- -"$APP_PID" 2>/dev/null || true
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
    pkill -f '[p]ython.*\/home\/user\/app.py' 2>/dev/null || true
    sleep 0.5
    rm -f /home/user/integration_result.log /tmp/ruby_request.json

    cat <<'MOCK_EOF' > /tmp/mock_api.py
import json
import secrets
from http.server import BaseHTTPRequestHandler, HTTPServer

capture_path = "/tmp/ruby_request.json"

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        result = secrets.randbelow(900000000) + 100000000
        capture = {
            "path": self.path,
            "content_type": self.headers.get("Content-Type", ""),
            "body": json.loads(raw.decode("utf-8")),
            "response_result": result,
        }
        with open(capture_path, "w") as f:
            json.dump(capture, f)
        payload = json.dumps({"result": result}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):
        pass

HTTPServer(("127.0.0.1", 5000), Handler).handle_request()
MOCK_EOF

    python3 /tmp/mock_api.py >/tmp/mock_api.log 2>&1 &
    MOCK_PID=$!
    wait_for_port || return 1
    timeout 20 ruby /home/user/test_e2e.rb >/tmp/mock_ruby.log 2>&1 || return 1
    wait "$MOCK_PID" || return 1
    MOCK_PID=""

    python3 - <<'PY' || return 1
import json
import os

expected_graph = {
    "nodes": {
        "A": {"type": "value", "value": 7},
        "B": {"type": "value", "value": 3},
        "C": {"type": "add", "inputs": ["A", "B"]},
        "D": {"type": "mul", "inputs": ["C", "A"]},
        "E": {"type": "add", "inputs": ["D", "B"]},
    },
    "target": "E",
}

assert os.path.isfile("/tmp/ruby_request.json"), "Ruby script did not send an HTTP request"
with open("/tmp/ruby_request.json") as f:
    capture = json.load(f)
assert capture["path"] == "/api/v1/compute"
assert capture["content_type"].split(";", 1)[0].strip().lower() == "application/json"
assert capture["body"] == expected_graph

expected_log = f'Result: {capture["response_result"]}, Status: 200'
assert os.path.isfile("/home/user/integration_result.log")
with open("/home/user/integration_result.log") as f:
    raw = f.read()
assert raw in (expected_log, expected_log + "\n"), (expected_log, raw)
PY
}

if run_verification; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
