#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import socket
import subprocess
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

SCRIPT_PATH = "/home/user/monitor_daemon.sh"
ENDPOINTS_PATH = "/home/user/endpoints.txt"
STATUS_PATH = "/home/user/status.log"
LOG_PATH = "/home/user/monitor.log"


def run_daemon(timeout=15):
    try:
        return subprocess.run(
            [SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            text=True,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(
            f"Script {SCRIPT_PATH} timed out after {timeout} seconds. "
            "The infinite recursion bug might not be fixed."
        )


def assert_completed(result):
    assert result.returncode == 0, (
        f"Script {SCRIPT_PATH} exited with non-zero code {result.returncode}. "
        f"Stderr: {result.stderr}"
    )
    assert os.path.isfile(STATUS_PATH), f"Status log {STATUS_PATH} was not created."
    with open(STATUS_PATH, "r") as f:
        content = f.read()
    assert "MONITORING COMPLETE" in content, (
        f"'MONITORING COMPLETE' not found in {STATUS_PATH}."
    )


def test_resolution_file():
    path = "/home/user/resolution.txt"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f.read().strip().splitlines()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {path}, found {len(lines)}."
    assert lines[0] == "http://127.0.0.1:8080/timeout", (
        f"First line of {path} is incorrect. Expected "
        f"'http://127.0.0.1:8080/timeout', got '{lines[0]}'."
    )
    assert lines[1] == "FIXED", (
        f"Second line of {path} is incorrect. Expected 'FIXED', got '{lines[1]}'."
    )


def test_monitor_daemon_execution():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."
    result = run_daemon()
    assert_completed(result)


def test_dynamic_endpoints_get_exactly_three_retries_each_and_processing_continues():
    token = uuid.uuid4().hex
    fail_paths = [f"/fail-{token}-a", f"/fail-{token}-b"]
    ok_path = f"/ok-{token}"
    counts = {fail_paths[0]: 0, fail_paths[1]: 0, ok_path: 0}
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            with lock:
                if self.path in counts:
                    counts[self.path] += 1

            if self.path in fail_paths:
                # Deliberately terminate the HTTP exchange so curl reports a
                # transport failure immediately, without relying on fixed timing.
                try:
                    self.connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                self.connection.close()
                return

            if self.path == ok_path:
                self.send_response(200)
                self.send_header("Content-Length", "2")
                self.end_headers()
                self.wfile.write(b"OK")
                return

            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()

        def log_message(self, format, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]

    fail_urls = [f"http://127.0.0.1:{port}{path}" for path in fail_paths]
    ok_url = f"http://127.0.0.1:{port}{ok_path}"

    with open(ENDPOINTS_PATH, "rb") as f:
        original_endpoints = f.read()

    try:
        with open(ENDPOINTS_PATH, "w") as f:
            f.write(fail_urls[0] + "\n")
            f.write(fail_urls[1] + "\n")
            f.write(ok_url + "\n")

        result = run_daemon()
        assert_completed(result)
    finally:
        with open(ENDPOINTS_PATH, "wb") as f:
            f.write(original_endpoints)
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    # Each failing endpoint must receive one initial attempt plus exactly three
    # retries. The succeeding endpoint proves processing continued afterward.
    assert counts[fail_paths[0]] == 4, (
        f"Expected 1 initial attempt and exactly 3 retries for {fail_urls[0]}, "
        f"but observed {counts[fail_paths[0]]} requests."
    )
    assert counts[fail_paths[1]] == 4, (
        f"Expected 1 initial attempt and exactly 3 retries for {fail_urls[1]}, "
        f"but observed {counts[fail_paths[1]]} requests."
    )
    assert counts[ok_path] == 1, (
        f"Expected the daemon to continue and check {ok_url} once, "
        f"but observed {counts[ok_path]} requests."
    )

    assert os.path.isfile(LOG_PATH), f"Monitor log {LOG_PATH} was not created."
    with open(LOG_PATH, "r") as f:
        log_content = f.read()
    for url in fail_urls + [ok_url]:
        assert url in log_content, f"Expected {url} to be recorded in {LOG_PATH}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
