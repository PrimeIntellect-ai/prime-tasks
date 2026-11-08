#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest


def test_nginx_config_fixed():
    config_path = "/app/nginx/nginx.conf"
    assert os.path.isfile(config_path), f"Nginx config missing at {config_path}"

    with open(config_path, "r") as f:
        content = f.read()

    match = re.search(r"proxy_pass\s+http://(?:127\.0\.0\.1|localhost):5000/?;", content)
    assert match is not None, "Nginx config was not updated to point to the correct Flask API port (5000)."


def test_nginx_actually_routes_to_api():
    subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["pkill", "-f", "gunicorn.*app:app"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.2)

    result = subprocess.run(["/app/start_services.sh"], capture_output=True, text=True, timeout=8)
    assert result.returncode == 0, (
        f"start_services.sh failed with {result.returncode}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )

    last_error = None
    for _ in range(12):
        try:
            with urllib.request.urlopen("http://127.0.0.1:8080/health", timeout=3) as response:
                assert response.status == 200
                payload = json.loads(response.read().decode("utf-8"))
                assert payload.get("status") == "ok"
                assert payload.get("db_status") in {"connected", "disconnected"}
                return
        except Exception as exc:
            last_error = exc
            time.sleep(0.2)
    pytest.fail(f"Nginx did not successfully proxy /health to the API: {last_error}")


class ReusableThreadingHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def test_monitor_execution_and_performance():
    monitor_path = "/home/user/monitor.py"
    assert os.path.isfile(monitor_path), f"Monitor script missing at {monitor_path}"

    # Replace the real stack with a controlled endpoint so the report can be
    # checked against requests and responses actually observed by the verifier.
    subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.2)

    rng = random.SystemRandom()
    successful_count = rng.randint(45, 65)
    disconnected_count = rng.randint(10, 20)
    malformed_count = rng.randint(7, 12)
    timeout_count = 10
    http_error_count = 100 - successful_count - disconnected_count - malformed_count - timeout_count
    assert http_error_count > 0

    response_plan = (
        ["connected"] * successful_count
        + ["disconnected"] * disconnected_count
        + ["malformed"] * malformed_count
        + ["timeout"] * timeout_count
        + ["http_error"] * http_error_count
    )
    rng.shuffle(response_plan)

    state = {"next": 0, "hits": 0}
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            pass

        def do_GET(self):
            with lock:
                state["hits"] += 1
                index = state["next"]
                state["next"] += 1

            if self.path != "/health" or index >= len(response_plan):
                self.send_response(404)
                self.end_headers()
                return

            kind = response_plan[index]
            if kind == "timeout":
                # The supplied monitor used a one-second request timeout; a
                # two-second API response must be caught and counted as failed.
                time.sleep(2.0)
                status = 200
                body = b'{"status":"ok","db_status":"connected"}'
            elif kind == "connected":
                status = 200
                body = b'{"status":"ok","db_status":"connected"}'
            elif kind == "disconnected":
                status = 200
                body = b'{"status":"ok","db_status":"disconnected"}'
            elif kind == "malformed":
                status = 200
                body = b'{not valid json'
            else:
                status = 503
                body = b'{"status":"error","db_status":"connected"}'

            try:
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass

    server = ReusableThreadingHTTPServer(("127.0.0.1", 8080), Handler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    report_path = "/home/user/report.json"
    if os.path.exists(report_path):
        os.remove(report_path)

    try:
        start_time = time.perf_counter()
        result = subprocess.run(
            ["python3", monitor_path], capture_output=True, text=True, timeout=4
        )
        execution_time = time.perf_counter() - start_time
    finally:
        server.shutdown()
        server.server_close()
        server_thread.join(timeout=1)

    assert result.returncode == 0, (
        f"FAILED: Script exited with {result.returncode}\n"
        f"stderr: {result.stderr}\nstdout: {result.stdout}"
    )
    assert execution_time <= 3.0, (
        f"FAILED: execution_time={execution_time:.2f}s (Threshold: <=3.0s). "
        "The script is not sufficiently optimized for concurrency."
    )
    assert state["hits"] == 100, (
        f"FAILED: Expected the monitor to issue exactly 100 HTTP requests, observed {state['hits']}"
    )
    assert state["next"] == 100, "FAILED: Not all planned health responses were exercised"
    assert os.path.exists(report_path), f"FAILED: Report file {report_path} was not created."

    try:
        with open(report_path, "r") as f:
            report = json.load(f)
    except Exception as exc:
        pytest.fail(f"FAILED: Could not read or parse report.json: {exc}")

    assert set(report) == {"total_requests", "successful_requests", "failed_requests"}, \
        "FAILED: report.json does not have the required exact fields"
    total_requests = report.get("total_requests")
    assert total_requests == 100, f"FAILED: Expected 100 total requests, got {total_requests}"
    assert "successful_requests" in report, "FAILED: 'successful_requests' missing in report.json"
    assert "failed_requests" in report, "FAILED: 'failed_requests' missing in report.json"
    assert report["successful_requests"] + report["failed_requests"] == 100, \
        "FAILED: successful_requests + failed_requests must equal 100"

    assert report["successful_requests"] == successful_count, (
        "FAILED: successful_requests must count only HTTP 200 responses containing valid JSON "
        "with db_status == 'connected'"
    )
    assert report["failed_requests"] == 100 - successful_count, (
        "FAILED: timeouts, HTTP errors, malformed JSON, and disconnected db_status responses "
        "must all be counted as failures"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
