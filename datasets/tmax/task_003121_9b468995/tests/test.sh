#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
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
import json
import os
import socket
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
import pytest
import redis
import requests

PROBLEM_URL = "http://127.0.0.1:8080/api/v1/search?q=test_prefix***"
PROBLEM_PATH = "/api/v1/search?q=test_prefix***"


def test_nginx_config_updated():
    config_path = "/app/nginx/nginx.conf"
    assert os.path.isfile(config_path), f"{config_path} does not exist"
    with open(config_path, "r") as f:
        content = f.read()
    assert "proxy_read_timeout 10s;" in content, "proxy_read_timeout is not set to 10s in nginx.conf"


def test_regression_test_script_exists_and_behaves_correctly():
    script_path = "/home/user/regression_test.py"
    assert os.path.isfile(script_path), f"{script_path} does not exist"

    subprocess.run(
        ["nginx", "-c", "/app/nginx/nginx.conf", "-s", "stop"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    time.sleep(0.5)

    class CaptureHandler(BaseHTTPRequestHandler):
        paths = []
        active = 0
        max_active = 0
        fail_at = None
        lock = threading.Lock()

        def do_GET(self):
            with type(self).lock:
                type(self).active += 1
                type(self).max_active = max(type(self).max_active, type(self).active)
                request_number = len(type(self).paths) + 1
                type(self).paths.append(self.path)
            try:
                time.sleep(0.02)
                status = 500 if type(self).fail_at == request_number else 200
                body = b"[]"
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            finally:
                with type(self).lock:
                    type(self).active -= 1

        def log_message(self, *args):
            pass

    server = None
    try:
        for _ in range(20):
            try:
                server = ThreadingHTTPServer(("127.0.0.1", 8080), CaptureHandler)
                break
            except OSError:
                time.sleep(0.1)
        assert server is not None, "Could not bind controlled regression-test server to port 8080"

        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        CaptureHandler.paths = []
        CaptureHandler.active = 0
        CaptureHandler.max_active = 0
        CaptureHandler.fail_at = None
        success_run = subprocess.run(["python3", script_path], timeout=20)
        assert success_run.returncode == 0, "Regression script must exit 0 when all 50 requests return HTTP 200"
        assert len(CaptureHandler.paths) == 50, f"Regression script sent {len(CaptureHandler.paths)} requests instead of 50"
        assert all(path == PROBLEM_PATH for path in CaptureHandler.paths), "Regression script did not use the exact problematic query"
        assert CaptureHandler.max_active == 1, "Regression script requests were not sequential"

        CaptureHandler.paths = []
        CaptureHandler.active = 0
        CaptureHandler.max_active = 0
        CaptureHandler.fail_at = 25
        failure_run = subprocess.run(["python3", script_path], timeout=20)
        assert failure_run.returncode == 1, "Regression script must exit 1 when a request does not return HTTP 200"
        assert len(CaptureHandler.paths) == 50, f"Regression script sent {len(CaptureHandler.paths)} requests instead of 50 on failure"
        assert all(path == PROBLEM_PATH for path in CaptureHandler.paths), "Regression script did not use the exact problematic query"
        assert CaptureHandler.max_active == 1, "Regression script requests were not sequential"
    finally:
        if server is not None:
            server.shutdown()
            server.server_close()
        restarted = subprocess.run(
            ["nginx", "-c", "/app/nginx/nginx.conf"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert restarted.returncode == 0, f"Failed to restart nginx: {restarted.stderr}"
        time.sleep(0.5)


def test_resolution_json_correct():
    json_path = "/home/user/resolution.json"
    assert os.path.isfile(json_path), f"{json_path} does not exist"
    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} is not a valid JSON file")

    assert "problematic_endpoint" in data, "Missing 'problematic_endpoint' in resolution.json"
    assert "root_cause_function" in data, "Missing 'root_cause_function' in resolution.json"
    assert data["problematic_endpoint"] == PROBLEM_PATH, f"Incorrect problematic_endpoint: {data['problematic_endpoint']}"
    assert data["root_cause_function"].lower() == "keys", f"Incorrect root_cause_function: {data['root_cause_function']}"


def test_search_returns_redis_derived_results():
    client = redis.Redis(host="127.0.0.1", port=6379, db=0, decode_responses=True)
    token = uuid.uuid4().hex
    prefix = f"verifier_{token}_"
    expected = {f"{prefix}{i}" for i in range(17)}
    decoys = {f"other_{token}_{i}" for i in range(5)}
    try:
        client.mset({key: f"value-{i}" for i, key in enumerate(expected | decoys)})
        response = requests.get(
            "http://127.0.0.1:8080/api/v1/search",
            params={"q": prefix},
            timeout=5,
        )
        assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
        payload = response.json()
        assert isinstance(payload, list), "Search response is not a JSON list"
        assert set(payload) == expected, f"Search response did not match Redis contents: {payload}"
        assert len(payload) == len(expected), "Search response contains duplicate or missing results"
    finally:
        if expected or decoys:
            client.delete(*(expected | decoys))


def test_latency_metric_threshold_and_problematic_results():
    client = redis.Redis(host="127.0.0.1", port=6379, db=0, decode_responses=True)
    token = uuid.uuid4().hex
    inserted = {f"test_prefix_verifier_{token}_{i}" for i in range(60)}
    client.mset({key: "1" for key in inserted})

    latencies = []
    try:
        for _ in range(100):
            start = time.perf_counter()
            try:
                resp = requests.get(PROBLEM_URL, timeout=5)
            except requests.exceptions.RequestException as exc:
                pytest.fail(f"Request failed: {exc}")
            latencies.append((time.perf_counter() - start) * 1000)
            assert resp.status_code == 200, f"Expected HTTP 200, got {resp.status_code}"
            payload = resp.json()
            assert isinstance(payload, list), "Search response is not a JSON list"
            assert len(payload) == 50, f"Expected 50 matching results, got {len(payload)}"
            assert len(set(payload)) == 50, "Search response contains duplicate results"
            assert all(key.startswith("test_prefix") for key in payload), "Search returned a non-matching key"
            assert all(client.exists(key) for key in payload), "Search returned a key not present in Redis"

        p95_latency = np.percentile(latencies, 95)
        assert p95_latency <= 100.0, f"P95 latency was {p95_latency:.2f}ms, which exceeds the threshold of 100.0ms."
    finally:
        client.delete(*inserted)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
