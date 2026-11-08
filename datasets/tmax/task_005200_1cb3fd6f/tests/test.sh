#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import os
import socket
import stat
import subprocess
import time
import uuid

import pytest
import redis
import requests

REPRO = "/home/user/repro.py"
LOG = "/app/logs/processed.log"
LOGGER = "/app/processor/logger.js"
CAPTURE = "/tmp/repro_capture.json"


def stop_services():
    subprocess.run(["pkill", "-x", "node"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "uvicorn"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["redis-cli", "shutdown", "nosave"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)


def wait_port(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"Port {port} did not become ready")


def validate_and_flatten(payload):
    assert isinstance(payload, dict), "repro.py must submit a JSON object"
    assert "error" in payload and isinstance(payload["error"], dict), (
        "repro.py must submit a non-null error object that reaches extractCausation"
    )
    assert len(json.dumps(payload)) <= 65536, "The reproduction payload is not minimal"

    event = payload.get("event", "unknown")
    if not event:
        event = "unknown"
    assert isinstance(event, str) and len(event) <= 200 and "\n" not in event and "\r" not in event

    messages = []
    current = payload["error"]
    for _ in range(33):
        assert isinstance(current, dict), "Causation links must be JSON objects"
        if "message" in current:
            assert isinstance(current["message"], str), "Error messages must be strings"
            assert "\n" not in current["message"] and "\r" not in current["message"]
            if current["message"]:
                messages.append(current["message"])

        inner = current.get("innerError")
        cause = current.get("cause")
        assert inner is None or isinstance(inner, dict), "innerError must be an object or null"
        assert cause is None or isinstance(cause, dict), "cause must be an object or null"

        # JavaScript treats even an empty object as truthy and prioritizes innerError.
        if isinstance(inner, dict):
            current = inner
        elif isinstance(cause, dict):
            current = cause
        else:
            assert messages, "The reproduction should contain at least one error message"
            return event, " -> ".join(messages)
    pytest.fail("The reproduction payload is unnecessarily deep")


def test_complete_task():
    assert os.path.isfile(REPRO), (
        "/home/user/repro.py is missing. You must create a script to reproduce the issue."
    )
    assert os.path.isfile(LOGGER), f"{LOGGER} is missing"
    mode = os.lstat(LOGGER).st_mode
    assert stat.S_ISREG(mode) and not os.path.islink(LOGGER), f"{LOGGER} must be a regular JavaScript file"
    syntax = subprocess.run(["node", "--check", LOGGER], capture_output=True, text=True)
    assert syntax.returncode == 0, f"logger.js has invalid syntax:\n{syntax.stderr}"

    stop_services()
    try:
        if os.path.exists(CAPTURE):
            os.unlink(CAPTURE)

        capture_source = r'''
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != '/submit_log':
            self.send_response(404); self.end_headers(); return
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if length <= 0 or length > 65536:
                raise ValueError('invalid body size')
            raw = self.rfile.read(length)
            payload = json.loads(raw.decode('utf-8'))
            with open('/tmp/repro_capture.json.tmp', 'w') as f:
                json.dump(payload, f)
            import os
            os.replace('/tmp/repro_capture.json.tmp', '/tmp/repro_capture.json')
            body = b'{"status":"queued"}'
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception:
            self.send_response(400); self.end_headers()
    def log_message(self, *args):
        pass

HTTPServer(('127.0.0.1', 8000), Handler).handle_request()
'''
        with open("/tmp/capture_api.py", "w") as f:
            f.write(capture_source)
        os.chmod("/tmp/capture_api.py", 0o700)

        capture_proc = subprocess.Popen(
            ["python3", "/tmp/capture_api.py"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        wait_port(8000)
        try:
            repro_run = subprocess.run(
                ["runuser", "-u", "user", "--", "python3", REPRO],
                cwd="/home/user",
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert repro_run.returncode == 0, (
                f"repro.py did not successfully send its request.\n"
                f"stdout: {repro_run.stdout}\nstderr: {repro_run.stderr}"
            )
            capture_proc.wait(timeout=3)
        finally:
            if capture_proc.poll() is None:
                capture_proc.terminate()
                capture_proc.wait(timeout=2)

        assert os.path.isfile(CAPTURE), (
            "repro.py did not POST JSON to http://127.0.0.1:8000/submit_log"
        )
        with open(CAPTURE) as f:
            repro_payload = json.load(f)
        repro_event, repro_chain = validate_and_flatten(repro_payload)

        # Execute the original, unpatched extraction logic on the payload actually
        # emitted by repro.py. A valid reproduction must make it run indefinitely.
        unpatched = r'''
const fs = require('fs');
function extractCausation(errorObj) {
    let causes = [];
    let current = errorObj;
    while (current != null) {
        if (current.message) causes.push(current.message);
        if (current.innerError) {
            current = current.innerError;
        } else if (current.cause) {
            current = current.cause;
        }
    }
    return causes.join(' -> ');
}
const payload = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
extractCausation(payload.error);
'''
        with open("/tmp/unpatched_logger_repro.js", "w") as f:
            f.write(unpatched)
        hang = subprocess.run(
            ["timeout", "2s", "node", "/tmp/unpatched_logger_repro.js", CAPTURE],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert hang.returncode == 124, (
            "The payload sent by repro.py does not hang the original unpatched extraction logic"
        )

        # Start clean service processes and execute the submitted logger.js itself.
        subprocess.run(["redis-server", "--daemonize", "yes"], check=True)
        deadline = time.time() + 5
        r = redis.Redis(host="127.0.0.1", port=6379, db=0)
        while True:
            try:
                r.ping()
                break
            except redis.RedisError:
                if time.time() >= deadline:
                    pytest.fail("Redis failed to start")
                time.sleep(0.1)
        r.flushall()

        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "w"):
            pass

        api_proc = subprocess.Popen(
            ["uvicorn", "main:app", "--host", "127.0.0.1", "--port", "8000"],
            cwd="/app/api",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        logger_proc = subprocess.Popen(
            ["node", LOGGER],
            cwd="/app/processor",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        wait_port(8000)
        time.sleep(0.3)
        assert logger_proc.poll() is None, "logger.js exited instead of running the queue processor"

        token = uuid.uuid4().hex
        fixed_payload = {
            "event": "test_event",
            "error": {
                "message": "DB Connection Failed",
                "cause": {"message": "Timeout"},
            },
        }

        deep_error = {"message": f"leaf-{token}"}
        deep_messages = [f"leaf-{token}"]
        for i in range(24, -1, -1):
            message = f"depth-{i}-{token}"
            link = "innerError" if i % 2 else "cause"
            deep_error = {"message": message, link: deep_error}
            deep_messages.insert(0, message)
        deep_payload = {"event": f"deep-{token}", "error": deep_error}

        for payload in (fixed_payload, deep_payload, repro_payload):
            try:
                response = requests.post(
                    "http://127.0.0.1:8000/submit_log", json=payload, timeout=5
                )
                assert response.status_code == 200, (
                    f"Expected status code 200, got {response.status_code}"
                )
            except requests.RequestException as exc:
                pytest.fail(f"Failed to send POST request to API. Is the API running? Error: {exc}")

        # This random payload bypasses the API, proving the executed Node artifact
        # really consumes Redis and writes the processed output.
        direct_payload = {
            "event": f"direct-{token}",
            "error": {
                "message": f"outer-{token}",
                "innerError": {
                    "message": f"middle-{token}",
                    "cause": {"message": f"terminal-{token}"},
                },
            },
        }
        r.lpush("log_queue", json.dumps(direct_payload))

        expected_lines = {
            "Event: test_event | Chain: DB Connection Failed -> Timeout",
            f"Event: deep-{token} | Chain: " + " -> ".join(deep_messages),
            f"Event: {repro_event} | Chain: {repro_chain}",
            f"Event: direct-{token} | Chain: outer-{token} -> middle-{token} -> terminal-{token}",
        }

        deadline = time.time() + 10
        actual_lines = set()
        while time.time() < deadline:
            if os.path.isfile(LOG):
                with open(LOG) as f:
                    actual_lines = set(f.read().splitlines())
                if expected_lines.issubset(actual_lines):
                    break
            if logger_proc.poll() is not None:
                pytest.fail("logger.js crashed while processing the test payloads")
            time.sleep(0.1)

        assert os.path.isfile(LOG), (
            f"{LOG} does not exist. The processor might not be running or failed to create the log file."
        )
        assert expected_lines.issubset(actual_lines), (
            f"Expected processed lines were not found in {LOG}.\n"
            f"Missing: {sorted(expected_lines - actual_lines)}\n"
            f"Actual: {sorted(actual_lines)}\n"
            "This indicates the processor is hanging or flattening causation chains incorrectly."
        )
    finally:
        stop_services()

PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
