#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
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
import ctypes
import json
import os
import random
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

import pytest
import requests

API = "http://127.0.0.1:8080/api/execute"


def post_batch(batch, timeout=10):
    response = requests.post(API, json={"batch": batch}, timeout=timeout)
    response.raise_for_status()
    data = response.json()
    assert set(data) == {"results"}, f"Unexpected response JSON: {data!r}"
    assert isinstance(data["results"], list)
    return data["results"]


def redis_cli(*args):
    proc = subprocess.run(
        ["/usr/bin/redis-cli", "-h", "127.0.0.1", "-p", "6379", "--raw", *args],
        text=True, capture_output=True, timeout=10
    )
    assert proc.returncode == 0, proc.stderr
    return proc.stdout.strip()


def test_libvm_exists_and_is_loadable():
    assert os.path.exists("/app/lib/libvm.so"), "Compiled shared library /app/lib/libvm.so not found."
    assert os.path.isfile("/app/lib/libvm.so"), "/app/lib/libvm.so is not a regular file."
    lib = ctypes.CDLL("/app/lib/libvm.so")
    assert hasattr(lib, "ExecuteBatch"), "libvm.so does not export ExecuteBatch."


def test_required_services_are_running():
    assert redis_cli("PING") == "PONG"
    for pattern, name in [('[n]ginx', 'nginx'), ('[g]unicorn', 'gunicorn'), ('[r]edis-server', 'redis-server')]:
        proc = subprocess.run(["pgrep", "-f", pattern], capture_output=True, text=True)
        assert proc.returncode == 0, f"{name} is not running"


def test_api_correctness_original_example():
    payload = {"batch": ["PUSH 5 PUSH 10 ADD", "PUSH 3 PUSH 4 MUL"]}
    try:
        response = requests.post(API, json=payload, timeout=5)
        response.raise_for_status()
        data = response.json()
        assert "results" in data, "Response JSON missing 'results' key"
        assert data["results"] == ["15", "12"], f"Expected ['15', '12'], got {data['results']}"
    except Exception as exc:
        pytest.fail(f"API correctness test failed: {exc}")


def make_cases(seed, count):
    rng = random.Random(seed)
    programs = []
    expected = []
    for _ in range(count):
        a = rng.randint(0, 5000)
        b = rng.randint(0, 5000)
        c = rng.randint(1, 20)
        if rng.randrange(2):
            programs.append(f"PUSH {a} PUSH {b} ADD PUSH {c} MUL")
            expected.append(str((a + b) * c))
        else:
            programs.append(f"PUSH {a} PUSH {b} MUL PUSH {c} ADD")
            expected.append(str(a * b + c))
    return programs, expected


def test_general_batch_evaluation_and_ordering():
    programs, expected = make_cases(917243, 80)
    assert post_batch(programs, timeout=15) == expected


def test_concurrent_requests_are_isolated_and_correct():
    jobs = [make_cases(10000 + i, 12 + (i % 9)) for i in range(36)]
    with ThreadPoolExecutor(max_workers=18) as pool:
        futures = {pool.submit(post_batch, programs, 15): expected for programs, expected in jobs}
        for future in as_completed(futures):
            assert future.result() == futures[future]


def test_python_ffi_declarations_and_concurrent_calls():
    sys.path.insert(0, "/app/backend")
    import ffi

    assert list(ffi.lib.ExecuteBatch.argtypes or []) == [ctypes.c_char_p], \
        "ExecuteBatch.argtypes must declare a single c_char_p argument"
    pointer_types = (ctypes.c_void_p, ctypes.POINTER(ctypes.c_char))
    assert ffi.lib.ExecuteBatch.restype in pointer_types, \
        "ExecuteBatch.restype must preserve the returned pointer so it can be freed"

    jobs = [make_cases(40000 + i, 25) for i in range(20)]
    with ThreadPoolExecutor(max_workers=12) as pool:
        futures = {pool.submit(ffi.execute_batch, programs): expected for programs, expected in jobs}
        for future in as_completed(futures):
            assert future.result() == futures[future]


def test_ffi_does_not_leak_returned_c_strings():
    code = r'''
import gc, sys
sys.path.insert(0, "/app/backend")
from ffi import execute_batch
batch = ["PUSH 999999 PUSH 999999 ADD"] * 1500
for _ in range(150):
    execute_batch(batch)
gc.collect()
def rss_kb():
    with open("/proc/self/status") as f:
        for line in f:
            if line.startswith("VmRSS:"):
                return int(line.split()[1])
start = rss_kb()
for _ in range(2500):
    execute_batch(batch)
gc.collect()
delta = rss_kb() - start
if delta > 16384:
    raise SystemExit("RSS grew by %d KiB; returned C strings appear not to be freed" % delta)
'''
    proc = subprocess.run([sys.executable, "-c", code], text=True, capture_output=True, timeout=90)
    assert proc.returncode == 0, proc.stdout + proc.stderr


def test_redis_cache_is_used_and_expires_within_60_seconds():
    assert redis_cli("FLUSHALL") == "OK"
    programs, expected = make_cases(772991, 17)
    assert post_batch(programs) == expected

    size_after_first = int(redis_cli("DBSIZE"))
    assert size_after_first >= 1, "First request did not create a Redis cache entry"
    keys = [k for k in redis_cli("--scan").splitlines() if k]
    assert keys, "No Redis cache key was created"
    ttls = [int(redis_cli("TTL", key)) for key in keys]
    assert any(1 <= ttl <= 60 for ttl in ttls), f"No cache entry has the required <=60 second TTL: {ttls}"

    assert redis_cli("CONFIG", "RESETSTAT") == "OK"
    assert post_batch(programs) == expected
    assert int(redis_cli("DBSIZE")) == size_after_first, "Identical request created another cache entry"
    info = redis_cli("INFO", "stats")
    match = re.search(r"^keyspace_hits:(\d+)\r?$", info, re.MULTILINE)
    assert match and int(match.group(1)) >= 1, "Repeated request did not read its result from Redis"


def test_benchmark_rps():
    lua = "/tmp/verifier_post.lua"
    with open(lua, "w") as f:
        f.write('wrk.method = "POST"\n')
        f.write('wrk.body = \'{"batch":["PUSH 5 PUSH 10 ADD","PUSH 3 PUSH 4 MUL"]}\'\n')
        f.write('wrk.headers["Content-Type"] = "application/json"\n')

    proc = subprocess.run(
        ["/usr/bin/wrk", "-t12", "-c400", "-d10s", "-s", lua, API],
        text=True, capture_output=True, timeout=25
    )
    assert proc.returncode == 0, f"wrk failed:\n{proc.stdout}\n{proc.stderr}"
    match = re.search(r"Requests/sec:\s+([\d.]+)", proc.stdout)
    assert match, f"Could not parse wrk output:\n{proc.stdout}\n{proc.stderr}"
    rps = float(match.group(1))
    assert rps >= 800, f"Measured throughput is {rps} RPS, which is below the required threshold of 800 RPS."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
