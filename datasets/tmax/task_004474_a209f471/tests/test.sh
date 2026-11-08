#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import json
import random
import ctypes
import urllib.request
import urllib.error
import subprocess
import pytest
import concurrent.futures


def knapsack_oracle(items, capacity):
    dp = [0] * (capacity + 1)
    for item in items:
        weight = item["weight"]
        value = item["value"]
        for current in range(capacity, weight - 1, -1):
            dp[current] = max(dp[current], dp[current - weight] + value)
    return dp[capacity]


def test_shared_library_and_bugfix():
    so_path = "/home/user/legacy/libsolver.so"
    assert os.path.exists(so_path), f"Shared library {so_path} was not compiled or is missing."

    c_path = "/home/user/legacy/solver.c"
    assert os.path.exists(c_path), f"Source file {c_path} is missing."
    with open(c_path, 'r') as f:
        content = f.read()
    assert "int dp[50]" not in content, "The memory safety bug (fixed-size array `int dp[50]`) is still present in solver.c"

    # Load and invoke the submitted shared object itself on unpredictable cases.
    lib = ctypes.CDLL(so_path)
    solve = lib.solve_knapsack
    solve.argtypes = [ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int), ctypes.c_int, ctypes.c_int]
    solve.restype = ctypes.c_int

    rng = random.SystemRandom()
    cases = []
    cases.append(([{"weight": 1 + (i % 31), "value": 3 + ((i * 17) % 101)} for i in range(73)], 1000))
    for _ in range(14):
        n = rng.randint(1, 100)
        capacity = rng.randint(51, 1000)
        cases.append(([{"weight": rng.randint(1, min(120, capacity)), "value": rng.randint(1, 500)} for _ in range(n)], capacity))

    for items, capacity in cases:
        weights = (ctypes.c_int * len(items))(*[x["weight"] for x in items])
        values = (ctypes.c_int * len(items))(*[x["value"] for x in items])
        actual = solve(weights, values, len(items), capacity)
        assert actual == knapsack_oracle(items, capacity), (
            f"libsolver.so returned {actual} for capacity {capacity}; expected {knapsack_oracle(items, capacity)}"
        )


def test_shared_library_does_not_leak_per_request():
    # Thousands of capacity-1000 calls expose a missing free while keeping the
    # check isolated from pytest's own allocator behavior.
    code = r'''
import ctypes, os
lib = ctypes.CDLL("/home/user/legacy/libsolver.so")
f = lib.solve_knapsack
f.argtypes = [ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int), ctypes.c_int, ctypes.c_int]
f.restype = ctypes.c_int
w = (ctypes.c_int * 1)(1)
v = (ctypes.c_int * 1)(1)
def rss_kb():
    with open("/proc/self/status") as h:
        for line in h:
            if line.startswith("VmRSS:"):
                return int(line.split()[1])
for _ in range(200):
    assert f(w, v, 1, 1000) == 1
before = rss_kb()
for _ in range(15000):
    assert f(w, v, 1, 1000) == 1
after = rss_kb()
assert after - before < 24 * 1024, (before, after)
'''
    result = subprocess.run(["python3", "-c", code], text=True, capture_output=True, timeout=30)
    assert result.returncode == 0, f"Repeated library calls indicate incorrect behavior or a memory leak: {result.stderr or result.stdout}"


@pytest.fixture(scope="module")
def api_server():
    start_sh = "/home/user/api/start.sh"
    assert os.path.exists(start_sh), f"{start_sh} does not exist."

    subprocess.run(["bash", start_sh], check=True)
    time.sleep(2)

    pid_file = "/home/user/api/server.pid"
    assert os.path.exists(pid_file), f"PID file {pid_file} was not created."
    with open(pid_file, 'r') as f:
        pid = int(f.read().strip())
    os.kill(pid, 0)

    # Retain a structural cgo check and verify that the running process really
    # has the submitted shared library loaded.
    server_go = "/home/user/api/server.go"
    assert os.path.exists(server_go), f"{server_go} does not exist."
    with open(server_go, "r") as f:
        source = f.read()
    assert re.search(r'import\s+"C"', source), "server.go does not import C and therefore does not use cgo"
    assert "#cgo" in source, "server.go has no cgo linker configuration"
    assert "solve_knapsack" in source, "server.go does not reference the C knapsack function"
    with open(f"/proc/{pid}/maps", "r") as f:
        maps = f.read()
    assert "libsolver.so" in maps, "The running Go server has not linked/loaded libsolver.so"

    yield

    try:
        os.kill(pid, 9)
    except Exception:
        pass


def post_json(url, data):
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode('utf-8'),
        headers={'Content-Type': 'application/json'}
    )
    try:
        with urllib.request.urlopen(req) as response:
            return response.getcode(), json.loads(response.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        return e.code, None
    except Exception:
        return 0, None


def test_api_valid_request(api_server):
    data = {
        "items": [
            {"weight": 10, "value": 60},
            {"weight": 20, "value": 100},
            {"weight": 30, "value": 120}
        ],
        "capacity": 50
    }
    code, resp = post_json("http://127.0.0.1:8080/solve", data)
    assert code == 200, f"Expected status 200 for a valid request, got {code}"
    assert resp is not None and resp.get("max_value") == 220, f"Expected max_value 220, got {resp}"


def test_api_validation(api_server):
    time.sleep(1.2)
    url = "http://127.0.0.1:8080/solve"

    data = {"items": [{"weight": 10, "value": 60}], "capacity": 1500}
    code, _ = post_json(url, data)
    assert code == 400, f"Expected 400 Bad Request for capacity > 1000, got {code}"

    data = {"items": [{"weight": 10, "value": 60}], "capacity": 0}
    code, _ = post_json(url, data)
    assert code == 400, f"Expected 400 Bad Request for capacity < 1, got {code}"

    data = {"items": [], "capacity": 50}
    code, _ = post_json(url, data)
    assert code == 400, f"Expected 400 Bad Request for empty items array, got {code}"

    time.sleep(1.2)
    data = {"items": [{"weight": 1, "value": 1}] * 101, "capacity": 50}
    code, _ = post_json(url, data)
    assert code == 400, f"Expected 400 Bad Request for more than 100 items, got {code}"

    data = {"items": [{"weight": 1, "value": 1}]}
    code, _ = post_json(url, data)
    assert code == 400, f"Expected 400 Bad Request for missing capacity, got {code}"


def test_api_randomized_knapsack_requests(api_server):
    url = "http://127.0.0.1:8080/solve"
    rng = random.SystemRandom()
    cases = [
        ({"items": [{"weight": 1 + (i % 37), "value": 5 + ((i * 29) % 211)} for i in range(100)], "capacity": 1000}),
        ({"items": [{"weight": 64, "value": 91}, {"weight": 71, "value": 103}, {"weight": 6, "value": 19}], "capacity": 137}),
    ]
    for _ in range(6):
        capacity = rng.randint(53, 999)
        n = rng.randint(2, 75)
        items = [{"weight": rng.randint(1, min(capacity, 150)), "value": rng.randint(1, 700)} for _ in range(n)]
        cases.append({"items": items, "capacity": capacity})

    for offset in range(0, len(cases), 4):
        time.sleep(1.2)
        for data in cases[offset:offset + 4]:
            expected = knapsack_oracle(data["items"], data["capacity"])
            code, resp = post_json(url, data)
            assert code == 200, f"Expected 200 for valid randomized request, got {code}"
            assert resp == {"max_value": expected}, f"Expected max_value {expected}, got {resp}"


def test_api_rate_limiting(api_server):
    url = "http://127.0.0.1:8080/solve"
    data = {"items": [{"weight": 10, "value": 60}], "capacity": 50}

    time.sleep(1.5)

    def make_request():
        return post_json(url, data)[0]

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        futures = [executor.submit(make_request) for _ in range(10)]
        for f in concurrent.futures.as_completed(futures):
            results.append(f.result())

    status_429_count = results.count(429)
    status_200_count = results.count(200)

    assert status_429_count > 0, f"Expected at least one 429 Too Many Requests status when sending 10 requests rapidly, got {results}"
    assert status_200_count <= 5, f"Expected at most 5 successful requests in a burst, got {status_200_count} (results: {results})"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
