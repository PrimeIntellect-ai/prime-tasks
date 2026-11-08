#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import math
import os
import re
import shutil
import subprocess
import sys
import textwrap
import time

import pytest

APP = "/app"
SO = "/app/libratelimit.so"
SPEEDUP = "/app/speedup.txt"

ORIGINAL_BENCHMARK = '''import time
from validator import PurePythonRateLimiter, CRateLimiter

def run_bench(limiter, iterations=500000):
    start = time.time()
    allowed = 0
    for _ in range(iterations):
        if limiter.allow_request():
            allowed += 1
    end = time.time()
    return end - start, allowed

py_limiter = PurePythonRateLimiter()
c_limiter = CRateLimiter()

print("Warming up...")
run_bench(py_limiter, 10000)
run_bench(c_limiter, 10000)

print("Benchmarking Python...")
py_time, py_allowed = run_bench(py_limiter)

print("Benchmarking C...")
c_time, c_allowed = run_bench(c_limiter)

speedup = py_time / c_time if c_time > 0 else 0
print(f"Python time: {py_time:.4f}s")
print(f"C time: {c_time:.4f}s")
print(f"Speedup: {speedup:.2f}x")

if speedup >= 5.0:
    print("Threshold met!")

with open('/app/speedup.txt', 'w') as f:
    f.write(str(speedup))
'''

ORIGINAL_PYTHON_LIMITER = '''
class PurePythonRateLimiter:
    def __init__(self):
        self.capacity = 500
        self.tokens = 500
        self.refill_rate = 10
        self.last_time = time.time() * 1000

    def allow_request(self):
        now = time.time() * 1000
        elapsed = now - self.last_time
        self.tokens += elapsed * self.refill_rate
        if self.tokens > self.capacity:
            self.tokens = self.capacity
        self.last_time = now

        if self.tokens >= 1:
            self.tokens -= 1
            return True
        return False
'''


def class_ast(source, name):
    tree = ast.parse(source)
    node = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == name)
    return ast.dump(node, include_attributes=False)


def test_sources_and_makefile_build_real_library():
    for path in ("/app/ratelimit.c", "/app/Makefile", "/app/validator.py", "/app/benchmark.py"):
        assert os.path.isfile(path), f"Required project file is missing: {path}"

    with open("/app/benchmark.py", "r") as f:
        assert f.read() == ORIGINAL_BENCHMARK, "benchmark.py was altered instead of implementing the requested artifacts"

    with open("/app/validator.py", "r") as f:
        validator_source = f.read()
    assert class_ast(validator_source, "PurePythonRateLimiter") == class_ast(
        ORIGINAL_PYTHON_LIMITER, "PurePythonRateLimiter"
    ), "The supplied Python baseline must not be slowed down or replaced"

    dry = subprocess.run(
        ["make", "-Bn", "-C", APP], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30
    )
    makefile_text = open("/app/Makefile", "r").read()
    build_description = makefile_text + "\n" + dry.stdout
    assert re.search(r"(?:^|\s)-fPIC(?:\s|$)", build_description), "Build must use -fPIC"
    assert re.search(r"(?:^|\s)-shared(?:\s|$)", build_description), "Build must produce a shared library"
    assert re.search(r"-D\s*OPTIMIZED_BUILD(?:\b|=)", build_description), "Build must define OPTIMIZED_BUILD"

    if os.path.lexists(SO):
        os.remove(SO)
    built = subprocess.run(
        ["make", "-B", "-C", APP], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=60
    )
    assert built.returncode == 0, f"make failed:\n{built.stdout}"
    assert os.path.isfile(SO), f"Expected shared library not found: {SO}. Ensure the Makefile builds it correctly."
    assert open(SO, "rb").read(4) == b"\x7fELF", "libratelimit.so is not an ELF binary"

    lib = ctypes.CDLL(SO)
    fn = lib.allow_request
    fn.argtypes = []
    fn.restype = ctypes.c_bool
    assert isinstance(fn(), bool), "allow_request must be an exported bool-returning, no-argument function"


def run_bucket_probe():
    probe_so = f"/tmp/libratelimit_probe_{os.getpid()}_{time.time_ns()}.so"
    shutil.copy2(SO, probe_so)
    code = r'''
import ctypes, json, math, sys, time
lib = ctypes.CDLL(sys.argv[1])
allow = lib.allow_request
allow.argtypes = []
allow.restype = ctypes.c_bool

start = time.monotonic()
first = [bool(allow()) for _ in range(30000)]
first_elapsed_ms = (time.monotonic() - start) * 1000.0

refill_start = time.monotonic()
time.sleep(0.025)
second = [bool(allow()) for _ in range(5000)]
refill_elapsed_ms = (time.monotonic() - refill_start) * 1000.0

for _ in range(20000):
    allow()
time.sleep(0.080)
burst_start = time.monotonic()
third = [bool(allow()) for _ in range(3000)]
burst_call_ms = (time.monotonic() - burst_start) * 1000.0

print(json.dumps({
    "first_allowed": sum(first),
    "first_rejected": len(first) - sum(first),
    "first_elapsed_ms": first_elapsed_ms,
    "second_allowed": sum(second),
    "refill_elapsed_ms": refill_elapsed_ms,
    "third_allowed": sum(third),
    "burst_call_ms": burst_call_ms,
}))
'''
    try:
        proc = subprocess.run(
            [sys.executable, "-c", code, probe_so], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert proc.returncode == 0, f"Shared-library behavior probe failed: {proc.stderr}"
        return json.loads(proc.stdout.strip())
    finally:
        if os.path.exists(probe_so):
            os.remove(probe_so)


def test_token_bucket_capacity_and_refill_behavior():
    result = run_bucket_probe()

    # Initially there are 500 tokens. Calls made while probing can add only
    # ten tokens per elapsed millisecond.
    assert result["first_allowed"] >= 500, "Bucket did not start with the specified 500-token capacity"
    assert result["first_rejected"] > 0, "Bucket never rejected requests after depletion"
    first_max = math.ceil(500 + 10 * result["first_elapsed_ms"]) + 20
    assert result["first_allowed"] <= first_max, "Initial burst exceeds capacity plus the specified refill"

    # A 25 ms pause should restore about 250 tokens, not zero and not a full
    # bucket. Include time spent making the measured calls in the upper bound.
    assert result["second_allowed"] >= 150, "Tokens did not refill at approximately 10 tokens per millisecond"
    second_max = math.ceil(10 * result["refill_elapsed_ms"]) + 20
    assert result["second_allowed"] <= second_max, "Refill rate is greater than 10 tokens per millisecond"

    # Eighty milliseconds is enough to refill fully, but capacity must remain
    # capped at 500 (apart from refill occurring while this burst is called).
    assert result["third_allowed"] >= 450, "Bucket did not refill to its 500-token capacity"
    third_max = math.ceil(500 + 10 * result["burst_call_ms"]) + 20
    assert result["third_allowed"] <= third_max, "Token count is not capped at the specified capacity of 500"


def test_validator_uses_the_shared_library():
    sys.path.insert(0, APP)
    try:
        sys.modules.pop("validator", None)
        import validator
        limiter = validator.CRateLimiter()
        shared = ctypes.CDLL(SO)
        shared.allow_request.argtypes = []
        shared.allow_request.restype = ctypes.c_bool

        results = [limiter.allow_request() for _ in range(5000)]
        assert all(type(v) is bool for v in results), "CRateLimiter.allow_request() must return Python booleans"
        assert sum(results) >= 400, "CRateLimiter did not expose the C bucket's initial capacity"
        assert sum(results) < len(results), "CRateLimiter did not enforce token depletion"

        # A second handle to the same library sees the same global bucket. If
        # CRateLimiter is a stub, this handle would still have about 500 tokens.
        directly_allowed = sum(bool(shared.allow_request()) for _ in range(1000))
        assert directly_allowed < 250, "CRateLimiter is not calling allow_request from libratelimit.so"
    finally:
        if APP in sys.path:
            sys.path.remove(APP)


def test_speedup_metric_is_fresh_finite_and_measured():
    if os.path.exists(SPEEDUP):
        os.remove(SPEEDUP)
    started_ns = time.time_ns()
    proc = subprocess.run(
        [sys.executable, "/app/benchmark.py"], cwd=APP, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
    )
    assert proc.returncode == 0, f"benchmark.py failed:\n{proc.stdout}"
    assert os.path.isfile(SPEEDUP), f"Expected output file not found: {SPEEDUP}"
    assert os.stat(SPEEDUP).st_mtime_ns >= started_ns, "speedup.txt was not produced by this benchmark run"

    try:
        content = open(SPEEDUP, "r").read().strip()
        speedup = float(content)
    except ValueError:
        pytest.fail(f"Could not parse the content of {SPEEDUP} as a float. Content: '{content}'")
    except Exception as exc:
        pytest.fail(f"Failed to read {SPEEDUP}: {exc}")

    assert math.isfinite(speedup), "Performance speedup must be a finite measured value"
    threshold = 5.0
    assert speedup >= threshold, (
        f"Performance speedup {speedup:.2f}x is less than the required threshold of {threshold}x. "
        "Ensure your C implementation is fully optimized and correctly integrated."
    )
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
