#!/bin/bash
set -e
mkdir -p /logs/verifier
mkdir -p /home/user/client_body /home/user/fastcgi_temp /home/user/proxy_temp /home/user/scgi_temp /home/user/uwsgi_temp

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import socket
import secrets
import shutil
import subprocess
import time
import threading
import urllib.request
from contextlib import contextmanager
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from zoneinfo import ZoneInfo

CONF_PATH = "/home/user/nginx.conf"
SCRIPT_PATH = "/home/user/monitor.py"
JSON_PATH = "/home/user/status.json"


def wait_for_port(port, process, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process.poll() is not None:
            stdout, stderr = process.communicate()
            raise AssertionError(f"Nginx exited before becoming ready. stdout={stdout!r}, stderr={stderr!r}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise AssertionError(f"Timed out waiting for port {port}")


@contextmanager
def running_gateway():
    token = secrets.token_hex(24).encode("ascii")
    state = {"requests": 0}

    class BackendHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            state["requests"] += 1
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(token)))
            self.end_headers()
            self.wfile.write(token)

        def log_message(self, format, *args):
            pass

    backend = HTTPServer(("127.0.0.1", 8080), BackendHandler)
    backend_thread = threading.Thread(target=backend.serve_forever, daemon=True)
    backend_thread.start()

    nginx = subprocess.Popen(
        ["nginx", "-c", CONF_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        wait_for_port(8081, nginx)
        yield token, state
    finally:
        if nginx.poll() is None:
            nginx.terminate()
            try:
                nginx.wait(timeout=5)
            except subprocess.TimeoutExpired:
                nginx.kill()
                nginx.wait(timeout=5)
        backend.shutdown()
        backend.server_close()
        backend_thread.join(timeout=5)


def test_nginx_conf_updated():
    conf_path = "/home/user/nginx.conf"
    assert os.path.isfile(conf_path), f"{conf_path} does not exist."
    with open(conf_path, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:8080;" in content, "nginx.conf does not contain the updated proxy_pass directive pointing to 8080."
    assert "proxy_pass http://127.0.0.1:9090;" not in content, "nginx.conf still contains the old proxy_pass directive pointing to 9090."

    syntax = subprocess.run(
        ["nginx", "-t", "-c", conf_path],
        capture_output=True,
        text=True,
    )
    assert syntax.returncode == 0, f"nginx.conf is not a valid Nginx configuration: {syntax.stderr}"

    with running_gateway() as (token, state):
        with urllib.request.urlopen("http://127.0.0.1:8081/", timeout=5) as response:
            body = response.read()
            assert response.status == 200
        assert body == token, "The gateway did not proxy the backend's dynamic response."
        assert state["requests"] == 1, "The request was not forwarded to the backend on port 8080."


def test_monitor_script_exists_and_executable():
    script_path = "/home/user/monitor.py"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def validate_status(data, started_at, finished_at):
    # Preserve the original schema/value assertions.
    assert "timezone" in data, "Missing 'timezone' in JSON output."
    assert data["timezone"] == "Asia/Tokyo", f"Expected timezone 'Asia/Tokyo', got {data['timezone']}"

    assert "timestamp" in data, "Missing 'timestamp' in JSON output."
    timestamp_pattern = r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+09:00$"
    assert re.match(timestamp_pattern, data["timestamp"]), f"Timestamp format is incorrect: {data['timestamp']}"

    assert "status_code" in data, "Missing 'status_code' in JSON output."
    assert data["status_code"] == 200, f"Expected status_code 200, got {data['status_code']}"

    assert "disk_usage_percent" in data, "Missing 'disk_usage_percent' in JSON output."
    assert isinstance(data["disk_usage_percent"], (int, float)), "disk_usage_percent must be a float or int."
    assert 0.0 <= float(data["disk_usage_percent"]) <= 100.0, "disk_usage_percent must be between 0 and 100."

    assert set(data) == {"timezone", "timestamp", "status_code", "disk_usage_percent"}, "status.json has an incorrect schema."

    reported_time = datetime.fromisoformat(data["timestamp"])
    assert reported_time.utcoffset().total_seconds() == 9 * 3600, "Timestamp is not in the +09:00 Tokyo offset."
    reported_epoch = reported_time.timestamp()
    assert started_at - 2 <= reported_epoch <= finished_at + 2, "Timestamp is not the current time."
    tokyo_now = datetime.fromtimestamp(reported_epoch, ZoneInfo("Asia/Tokyo"))
    assert tokyo_now.strftime("%Y-%m-%dT%H:%M:%S%z") == data["timestamp"].replace(":00", "00", 1) if False else True

    usage = shutil.disk_usage("/home/user")
    expected_percent = usage.used / usage.total * 100.0
    reported_percent = float(data["disk_usage_percent"])
    assert abs(reported_percent - expected_percent) <= 0.15, (
        f"disk_usage_percent {reported_percent} does not match actual usage {expected_percent:.6f}"
    )


def run_monitor_and_read(state):
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)

    requests_before = state["requests"]
    started_at = time.time()
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=15)
    finished_at = time.time()
    assert result.returncode == 0, f"Execution of {SCRIPT_PATH} failed with return code {result.returncode}. Stderr: {result.stderr}"
    assert state["requests"] > requests_before, "monitor.py did not perform an HTTP GET through the gateway."
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} was not created by the script."

    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{JSON_PATH} does not contain valid JSON."

    validate_status(data, started_at, finished_at)
    return data


def test_monitor_script_execution_and_output():
    probe_path = "/home/user/.verifier_disk_probe"
    try:
        with running_gateway() as (_, state):
            run_monitor_and_read(state)

            usage = shutil.disk_usage("/home/user")
            probe_size = min(128 * 1024 * 1024, max(16 * 1024 * 1024, usage.total // 400))
            probe_size = min(probe_size, max(1024 * 1024, usage.free // 20))
            chunk = b"\0" * (1024 * 1024)
            with open(probe_path, "wb") as probe:
                remaining = probe_size
                while remaining:
                    part = chunk if remaining >= len(chunk) else chunk[:remaining]
                    probe.write(part)
                    remaining -= len(part)
                probe.flush()
                os.fsync(probe.fileno())

            run_monitor_and_read(state)
    finally:
        if os.path.exists(probe_path):
            os.remove(probe_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
