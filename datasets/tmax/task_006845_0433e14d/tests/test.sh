#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import socket
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

ANALYZER = "/home/user/analyzer.py"
MOCK_SERVICE = "/home/user/mock_service.py"
JSON_PATH = "/home/user/optimal_route.json"
ENV_PATH = "/home/user/.finops_env"
LOG_PATH = "/home/user/connectivity_test.log"

CANONICAL = {
    "zone1": {"status": "up", "cost_per_10k_requests": 5.0, "latency_ms": 120},
    "zone2": {"status": "up", "cost_per_10k_requests": 8.0, "latency_ms": 45},
    "zone3": {"status": "up", "cost_per_10k_requests": 3.5, "latency_ms": 80},
    "zone4": {"status": "down", "cost_per_10k_requests": 1.0, "latency_ms": 10},
}

DYNAMIC = {
    "zone1": {"status": "up", "cost_per_10k_requests": 2.0, "latency_ms": 99},
    "zone2": {"status": "up", "cost_per_10k_requests": 1.0, "latency_ms": 40},
    "zone3": {"status": "down", "cost_per_10k_requests": 0.1, "latency_ms": 5},
    "zone4": {"status": "up", "cost_per_10k_requests": 0.5, "latency_ms": 100},
}


def _kill_port_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(int(pid), signal.SIGTERM)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except OSError:
            pass
    time.sleep(0.3)


def _wait_for_service():
    deadline = time.time() + 5
    last_error = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen("http://127.0.0.1:8080/zone1/cost_metrics", timeout=0.5) as response:
                return json.load(response)
        except Exception as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Service did not start on port 8080: {last_error}")


def _optimal(telemetry):
    qualifying = [
        (zone, metrics)
        for zone, metrics in telemetry.items()
        if metrics["status"] == "up" and metrics["latency_ms"] < 100
    ]
    return min(qualifying, key=lambda item: item[1]["cost_per_10k_requests"])[0]


class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True


def _start_controlled_service(telemetry):
    requests_seen = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests_seen.append(self.path)
            parts = self.path.split("?")[0].strip("/").split("/")
            data = {}
            if len(parts) == 2 and parts[1] == "cost_metrics" and parts[0] in telemetry:
                data = telemetry[parts[0]]
            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(data).encode())

        def log_message(self, format, *args):
            pass

    server = ReusableHTTPServer(("127.0.0.1", 8080), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, thread, requests_seen


def _run_analyzer(telemetry):
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)

    server, thread, requests_seen = _start_controlled_service(telemetry)
    try:
        result = subprocess.run(
            ["python3", ANALYZER],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"analyzer.py exited with {result.returncode}.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert os.path.isfile(JSON_PATH), "analyzer.py did not create optimal_route.json."
        with open(JSON_PATH) as f:
            output = json.load(f)

        required_paths = {f"/{zone}/cost_metrics" for zone in telemetry}
        assert required_paths.issubset(set(requests_seen)), (
            "analyzer.py did not query every required cost_metrics endpoint. "
            f"Observed requests: {requests_seen}"
        )

        expected_zone = _optimal(telemetry)
        expected_url = f"http://127.0.0.1:8080/{expected_zone}"
        assert output.get("target_url") == expected_url, (
            f"For supplied live telemetry, expected {expected_url}, got {output.get('target_url')}"
        )
        return server, thread
    except Exception:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        raise


def test_analyzer_script_exists():
    assert os.path.exists(ANALYZER), "The analyzer.py script is missing."
    assert os.path.isfile(ANALYZER), "/home/user/analyzer.py is not a file."


def test_mock_service_exists_and_serves_required_telemetry():
    assert os.path.isfile(MOCK_SERVICE), "The mock_service.py script is missing or is not a file."
    _kill_port_8080()
    process = subprocess.Popen(
        ["python3", MOCK_SERVICE],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        first = _wait_for_service()
        assert first == CANONICAL["zone1"]
        for zone, expected in CANONICAL.items():
            with urllib.request.urlopen(
                f"http://127.0.0.1:8080/{zone}/cost_metrics", timeout=2
            ) as response:
                assert response.status == 200
                assert json.load(response) == expected
        with urllib.request.urlopen("http://127.0.0.1:8080/zone3", timeout=2) as response:
            assert response.status == 200
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)
        _kill_port_8080()


def test_analyzer_executes_queries_all_zones_and_computes_optimum():
    _kill_port_8080()

    dynamic_server, dynamic_thread = _run_analyzer(DYNAMIC)
    dynamic_server.shutdown()
    dynamic_server.server_close()
    dynamic_thread.join(timeout=2)

    canonical_server, canonical_thread = _run_analyzer(CANONICAL)
    try:
        with open(LOG_PATH) as f:
            logged_status = f.read().strip()
        with urllib.request.urlopen("http://127.0.0.1:8080/zone3", timeout=2) as response:
            assert logged_status == str(response.status)
    finally:
        canonical_server.shutdown()
        canonical_server.server_close()
        canonical_thread.join(timeout=2)


def test_optimal_route_json():
    assert os.path.exists(JSON_PATH), f"{JSON_PATH} is missing."

    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{JSON_PATH} does not contain valid JSON.")

    expected_url = "http://127.0.0.1:8080/zone3"
    assert "target_url" in data, f"'target_url' key missing in {JSON_PATH}."
    assert data["target_url"] == expected_url, f"Expected target_url to be {expected_url}, but got {data['target_url']}."


def test_finops_env():
    assert os.path.exists(ENV_PATH), f"{ENV_PATH} is missing."

    with open(ENV_PATH, "r") as f:
        content = f.read().strip()

    expected_line = 'export DEFAULT_CLOUD_ZONE="http://127.0.0.1:8080/zone3"'
    expected_line_single = "export DEFAULT_CLOUD_ZONE='http://127.0.0.1:8080/zone3'"
    expected_line_no_quotes = "export DEFAULT_CLOUD_ZONE=http://127.0.0.1:8080/zone3"

    lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert len(lines) >= 1, f"{ENV_PATH} is empty."

    found = any(
        line == expected_line or line == expected_line_single or line == expected_line_no_quotes
        for line in lines
    )
    assert found, f"Could not find the correct export statement in {ENV_PATH}. Expected: {expected_line}"


def test_connectivity_log():
    assert os.path.exists(LOG_PATH), f"{LOG_PATH} is missing."

    with open(LOG_PATH, "r") as f:
        content = f.read().strip()

    assert content == "200", f"Expected {LOG_PATH} to contain exactly '200', but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
