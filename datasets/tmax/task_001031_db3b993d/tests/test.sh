#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop the supplied fixed-response services so the monitor can be exercised
# against verifier-controlled responses.
pkill -f '^python3 /app/server.py (8080|8081)$' 2>/dev/null || true
sleep 0.2

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer


def test_monitor_source_exists_and_compiles():
    source_path = "/app/monitor.go"
    assert os.path.exists(source_path), f"Go source {source_path} does not exist."
    assert os.path.isfile(source_path), f"{source_path} is not a file."

    result = subprocess.run(
        ["go", "build", "-o", "/tmp/monitor_from_source", source_path],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"{source_path} does not compile successfully: {result.stderr}"
    )


def test_monitor_binary_exists_and_size():
    """Check that /app/monitor exists, is executable, is a Go binary, and is <= 3,000,000 bytes."""
    monitor_path = "/app/monitor"
    assert os.path.exists(monitor_path), f"Compiled binary {monitor_path} does not exist."
    assert os.path.isfile(monitor_path), f"{monitor_path} is not a file."
    assert os.access(monitor_path, os.X_OK), f"{monitor_path} is not executable."

    size = os.path.getsize(monitor_path)
    threshold = 3000000
    assert size <= threshold, f"Binary size of {monitor_path} is {size} bytes, which exceeds the maximum allowed {threshold} bytes. Did you strip debug symbols?"

    result = subprocess.run(
        ["go", "version", monitor_path], capture_output=True, text=True, timeout=10
    )
    version_output = result.stdout + result.stderr
    assert result.returncode == 0 and re.search(r"\bgo1\.\d+", version_output), (
        f"{monitor_path} is not recognized as a compiled Go executable: {version_output}"
    )


class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True


class State:
    def __init__(self, status):
        self.status = status
        self.requests = []
        self.lock = threading.Lock()


class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        with self.server.state.lock:
            self.server.state.requests.append((self.command, self.path))
            status = self.server.state.status
        if self.path == "/health":
            self.send_response(status)
            self.end_headers()
            self.wfile.write(b"verifier health response")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *args):
        pass


def start_server(port, state):
    server = ReusableHTTPServer(("127.0.0.1", port), HealthHandler)
    server.state = state
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, thread


def run_and_check(monitor_path, nginx_state, api_state):
    status_path = "/app/status.txt"
    if os.path.exists(status_path):
        os.remove(status_path)

    before_nginx = len(nginx_state.requests)
    before_api = len(api_state.requests)
    result = subprocess.run(
        [monitor_path], capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"Execution of {monitor_path} failed with return code {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    assert os.path.exists(status_path), f"Output file {status_path} was not created by the monitor."

    with open(status_path, "r") as f:
        content = f.read().strip()

    expected_content = f"nginx: {nginx_state.status}, api: {api_state.status}"
    assert content == expected_content, (
        f"Content of {status_path} is '{content}', expected '{expected_content}'."
    )

    nginx_new = nginx_state.requests[before_nginx:]
    api_new = api_state.requests[before_api:]
    assert nginx_new == [("GET", "/health")], (
        f"Expected exactly one GET to nginx /health, observed {nginx_new}."
    )
    assert api_new == [("GET", "/health")], (
        f"Expected exactly one GET to api /health, observed {api_new}."
    )


def test_monitor_execution_and_output():
    """Exercise both the submitted source and final binary against verifier-controlled statuses."""
    choices = [201, 202, 401, 403, 404, 418, 500, 502, 503]
    nginx_status, api_status = random.SystemRandom().sample(choices, 2)
    nginx_state = State(nginx_status)
    api_state = State(api_status)

    nginx_server, nginx_thread = start_server(8080, nginx_state)
    api_server, api_thread = start_server(8081, api_state)
    try:
        run_and_check("/tmp/monitor_from_source", nginx_state, api_state)

        nginx_status, api_status = random.SystemRandom().sample(choices, 2)
        nginx_state.status = nginx_status
        api_state.status = api_status
        run_and_check("/app/monitor", nginx_state, api_state)
    finally:
        nginx_server.shutdown()
        api_server.shutdown()
        nginx_server.server_close()
        api_server.server_close()
        nginx_thread.join(timeout=5)
        api_thread.join(timeout=5)


def test_crontab_configuration():
    """Check that crontab.conf exists, is installed, and schedules the monitor every minute."""
    config_path = "/app/crontab.conf"
    assert os.path.exists(config_path), f"Cron configuration {config_path} does not exist."
    assert os.path.isfile(config_path), f"{config_path} is not a file."

    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab."

    crontab_content = result.stdout.strip()
    with open(config_path, "r") as f:
        config_content = f.read().strip()
    assert crontab_content == config_content, (
        f"The active crontab does not match {config_path}; the configuration file was not applied."
    )

    found = False
    for line in crontab_content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 6:
            schedule = " ".join(parts[:5])
            command = " ".join(parts[5:])
            if schedule == "* * * * *" and "/app/monitor" in command:
                found = True
                break

    assert found, "Crontab does not contain a job scheduling /app/monitor every minute (* * * * *)."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
