#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import concurrent.futures
import json
import math
import os
import secrets
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request

import numpy as np
import pytest
import redis
import websockets

URL = "http://localhost:8000/api/v1/matrix/determinant"
RNG = secrets.SystemRandom()


def is_port_open(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(("localhost", port)) == 0


def determinant(matrix):
    if len(matrix) == 1:
        return matrix[0][0]
    total = 0
    for column, value in enumerate(matrix[0]):
        minor = [row[:column] + row[column + 1:] for row in matrix[1:]]
        total += (-1 if column % 2 else 1) * value * determinant(minor)
    return total


def random_matrix(size):
    return [[RNG.randint(-7, 7) for _ in range(size)] for _ in range(size)]


def post_matrix(matrix, timeout=5):
    body = json.dumps({"matrix": matrix}).encode("utf-8")
    request = urllib.request.Request(
        URL, data=body, headers={"Content-Type": "application/json"}, method="POST"
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        assert response.status == 200
        result = json.loads(response.read().decode("utf-8"))
    assert "determinant" in result, "Response missing 'determinant' key"
    assert isinstance(result["determinant"], (int, float))
    return float(result["determinant"])


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except OSError:
            pass

    owners = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(name))
                    break
        except OSError:
            continue
    return owners


def test_services_running():
    assert is_port_open(6379), "Redis is not running on port 6379"
    assert is_port_open(8001), "Rust Math Engine is not running on port 8001"
    assert is_port_open(8000), "Python FastAPI Gateway is not running on port 8000"


def test_build_and_start_script_exists():
    path = "/home/user/app/build_and_start.sh"
    assert os.path.isfile(path), f"Script {path} does not exist"
    assert os.access(path, os.X_OK), f"Script {path} is not executable"


def test_rust_project_builds_in_release_mode():
    completed = subprocess.run(
        ["cargo", "build", "--release"],
        cwd="/home/user/app/rust_engine",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=300,
    )
    assert completed.returncode == 0, completed.stdout
    artifact = "/home/user/app/rust_engine/target/release/math_engine"
    assert os.path.isfile(artifact) and os.access(artifact, os.X_OK)


def test_service_protocols_and_rust_listener():
    engine_pids = listener_pids(8001)
    assert engine_pids, "No process owns the Rust engine listening socket"
    executables = []
    for pid in engine_pids:
        try:
            executables.append(os.path.realpath(f"/proc/{pid}/exe"))
        except OSError:
            pass
    assert any(os.path.basename(path) == "math_engine" for path in executables), (
        f"Port 8001 is not owned by the compiled Rust math_engine: {executables}"
    )

    with urllib.request.urlopen("http://localhost:8000/openapi.json", timeout=5) as response:
        document = json.loads(response.read().decode("utf-8"))
    route = document.get("paths", {}).get("/api/v1/matrix/determinant", {})
    assert "post" in route, "FastAPI does not expose the required POST route"


async def websocket_determinants(cases):
    results = []
    for matrix in cases:
        async with websockets.connect("ws://localhost:8001/math", open_timeout=5) as ws:
            await ws.send(json.dumps({"matrix": matrix}))
            raw = await asyncio.wait_for(ws.recv(), timeout=5)
            message = json.loads(raw)
            assert "determinant" in message
            results.append(float(message["determinant"]))
    return results


def test_dynamic_functional_correctness_through_engine_and_gateway():
    cases = [random_matrix(size) for size in (1, 2, 3, 4) for _ in range(2)]
    expected = [float(determinant(matrix)) for matrix in cases]

    engine_results = asyncio.run(websocket_determinants(cases))
    for actual, wanted in zip(engine_results, expected):
        assert math.isclose(actual, wanted, rel_tol=1e-9, abs_tol=1e-7), (
            f"Rust engine returned {actual}, expected {wanted}"
        )

    gateway_results = [post_matrix(matrix) for matrix in cases]
    for actual, wanted in zip(gateway_results, expected):
        assert math.isclose(actual, wanted, rel_tol=1e-9, abs_tol=1e-7), (
            f"Gateway returned {actual}, expected {wanted}"
        )


def test_gateway_writes_result_to_redis():
    client = redis.Redis(host="localhost", port=6379, socket_timeout=3)
    client.flushall()
    matrix = random_matrix(4)
    wanted = float(determinant(matrix))
    actual = post_matrix(matrix)
    assert math.isclose(actual, wanted, rel_tol=1e-9, abs_tol=1e-7)
    cached_entries = sum(redis.Redis(host="localhost", port=6379, db=db).dbsize() for db in range(16))
    assert cached_entries > 0, "Gateway returned without caching the result in Redis"


def test_gateway_depends_on_websocket_engine():
    # A fresh, uncached request must not succeed while the WebSocket engine is paused.
    redis.Redis(host="localhost", port=6379).flushall()
    matrix = random_matrix(4)
    pids = listener_pids(8001)
    assert pids
    for pid in pids:
        os.kill(pid, signal.SIGSTOP)
    try:
        with pytest.raises(Exception):
            post_matrix(matrix, timeout=1)
    finally:
        for pid in pids:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
        time.sleep(0.2)
    assert is_port_open(8001), "Rust engine did not remain running after communication test"


def test_functional_correctness():
    actual = post_matrix([[1, 2], [3, 4]])
    assert abs(actual - (-2.0)) < 1e-5, f"Expected determinant -2.0, got {actual}"


def test_latency_metric():
    data = json.dumps({"matrix": [[2, 0], [0, 2]]}).encode("utf-8")

    def fetch():
        request = urllib.request.Request(
            URL, data=data, headers={"Content-Type": "application/json"}, method="POST"
        )
        start = time.perf_counter()
        with urllib.request.urlopen(request, timeout=5) as response:
            assert response.status == 200
            result = json.loads(response.read().decode("utf-8"))
        assert "determinant" in result
        assert math.isclose(float(result["determinant"]), 4.0, rel_tol=0, abs_tol=1e-7)
        return (time.perf_counter() - start) * 1000

    latencies = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=50) as executor:
        futures = [executor.submit(fetch) for _ in range(1000)]
        for future in concurrent.futures.as_completed(futures):
            latencies.append(future.result())

    assert len(latencies) == 1000, "Did not complete 1000 requests"
    p95_latency = np.percentile(latencies, 95)
    assert p95_latency <= 25.0, (
        f"p95 latency is {p95_latency:.2f} ms, which exceeds the 25.0 ms threshold."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
