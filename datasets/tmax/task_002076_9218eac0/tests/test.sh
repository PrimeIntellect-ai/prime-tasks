#!/bin/bash
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
import textwrap

import pytest
import requests

URL = "http://127.0.0.1:8080/evaluate"
AUTH = {"Authorization": "Bearer eval-secret-777"}


def test_files_exist():
    assert os.path.isfile("/home/user/api.py"), "/home/user/api.py is missing."
    assert os.path.isfile("/home/user/bench.py"), "/home/user/bench.py is missing."

    log_file = "/home/user/bench_results.log"
    assert os.path.isfile(log_file), "/home/user/bench_results.log is missing."

    with open(log_file, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.split("\n") if line.strip()]
    assert len(lines) > 0, "bench_results.log is empty."

    last_line = lines[-1]
    assert re.match(r"^Benchmark completed: \d+(\.\d+)?s$", last_line), \
        f"Log output does not match expected format: {last_line}"


def test_makefile_was_repaired():
    path = "/app/fast-eval/c_src/Makefile"
    assert os.path.isfile(path), "Vendored Makefile is missing."
    content = open(path, encoding="utf-8").read()
    assert "libfasteval.so" in content, "Makefile does not define the required libfasteval.so target."
    assert "-fPIC" in content, "Makefile does not compile position-independent code with -fPIC."
    assert os.path.isfile("/app/fast-eval/c_src/libfasteval.so"), "The vendored shared library was not built."


def test_fast_eval_installed():
    try:
        import fast_eval
    except ImportError:
        pytest.fail("fast_eval is not installed or cannot be imported.")

    try:
        result = fast_eval.compute("ADD", 2, 3)
        assert result == 5, f"fast_eval.compute('ADD', 2, 3) returned {result}, expected 5."
    except Exception as e:
        pytest.fail(f"fast_eval.compute failed: {e}")

    assert hasattr(fast_eval, "_lib"), "fast_eval is not backed by the required ctypes C library."
    assert isinstance(fast_eval._lib, ctypes.CDLL), "fast_eval._lib is not a loaded C shared library."
    lib_name = os.path.realpath(str(fast_eval._lib._name))
    assert os.path.isfile(lib_name), f"Loaded fast_eval shared library does not exist: {lib_name}"
    assert os.path.basename(lib_name) == "libfasteval.so"

    cases = [
        ("ADD", 17, -9, 8),
        ("ADD", -31, -12, -43),
        ("SUB", 17, -9, 26),
        ("SUB", -31, 12, -43),
        ("MUL", 13, -7, -91),
        ("MUL", -11, -12, 132),
        ("MUL", 0, 999, 0),
    ]
    for op, a, b, expected in cases:
        assert fast_eval.compute(op, a, b) == expected
        assert fast_eval._lib.compute(op.encode(), a, b) == expected


def expected_expression(initial_a, initial_b, chain):
    value = initial_a + initial_b
    parts = [f"ADD({initial_a}, {initial_b})"]
    for op, operand in chain:
        parts.append(f"{op}({operand})")
        if op == "ADD":
            value += operand
        elif op == "SUB":
            value -= operand
        else:
            value *= operand
    return " | ".join(parts), value


def post_expression(expression):
    try:
        return requests.post(URL, headers=AUTH, json={"expression": expression}, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to API at {URL}: {e}")


def test_rest_api_valid_request():
    payload = {"expression": "ADD(5, 5) | MUL(10) | SUB(20)"}
    resp = post_expression(payload["expression"])
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Response: {resp.text}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail("Response is not valid JSON.")
    assert "result" in data, "Response JSON missing 'result' key."
    assert data["result"] == 80, f"Expected result 80, got {data['result']}."


def test_rest_api_varied_derived_expressions():
    cases = [
        expected_expression(10, 5, [("MUL", 3)]),
        expected_expression(-7, 12, [("SUB", 9), ("MUL", -4)]),
        expected_expression(23, -8, [("ADD", 11), ("SUB", -6), ("MUL", 2)]),
        expected_expression(0, 0, [("MUL", 91), ("ADD", -17)]),
    ]
    rng = random.Random(918273)
    for _ in range(12):
        a = rng.randint(-30, 30)
        b = rng.randint(-30, 30)
        chain = [(rng.choice(["ADD", "SUB", "MUL"]), rng.randint(-8, 8))
                 for _ in range(rng.randint(1, 5))]
        cases.append(expected_expression(a, b, chain))

    for expression, expected in cases:
        resp = post_expression(expression)
        assert resp.status_code == 200, \
            f"Expression {expression!r} returned {resp.status_code}: {resp.text}"
        try:
            data = resp.json()
        except ValueError:
            pytest.fail(f"Response for {expression!r} is not valid JSON: {resp.text}")
        assert data == {"result": expected}, \
            f"Expression {expression!r}: expected {{'result': {expected}}}, got {data!r}"


def test_rest_api_invalid_auth():
    headers = {"Authorization": "Bearer wrong-token"}
    payload = {"expression": "ADD(1, 1)"}
    try:
        resp = requests.post(URL, headers=headers, json=payload, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to API at {URL}: {e}")
    assert resp.status_code == 401, \
        f"Expected 401 Unauthorized, got {resp.status_code}. Response: {resp.text}"


def test_rest_api_missing_auth():
    payload = {"expression": "ADD(1, 1)"}
    try:
        resp = requests.post(URL, json=payload, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to API at {URL}: {e}")
    assert resp.status_code == 401, \
        f"Expected 401 Unauthorized for missing auth, got {resp.status_code}. Response: {resp.text}"


def test_server_is_bound_to_exact_loopback_address():
    listeners = []
    with open("/proc/net/tcp", encoding="ascii") as f:
        for line in list(f)[1:]:
            fields = line.split()
            local_address, state = fields[1], fields[3]
            address, port = local_address.split(":")
            if int(port, 16) == 8080 and state == "0A":
                listeners.append(address)
    assert "0100007F" in listeners, "No TCP listener is bound to 127.0.0.1:8080."
    assert "00000000" not in listeners, "The API is bound to 0.0.0.0 instead of exactly 127.0.0.1."


def test_benchmark_actually_runs_10000_parser_evaluations():
    shim_dir = "/tmp/bench_shim"
    counter = "/tmp/bench_compute_count"
    os.makedirs(shim_dir, exist_ok=True)
    if os.path.exists(counter):
        os.unlink(counter)

    shim = r'''
import atexit
import ctypes
import glob
import os

_candidates = []
for pattern in (
    "/usr/local/lib/python*/site-packages/libfasteval.so",
    "/usr/lib/python*/site-packages/libfasteval.so",
    "/root/.local/lib/python*/site-packages/libfasteval.so",
    "/home/user/.local/lib/python*/site-packages/libfasteval.so",
    "/app/fast-eval/c_src/libfasteval.so",
):
    _candidates.extend(glob.glob(pattern))
_candidates = [p for p in _candidates if os.path.isfile(p)]
if not _candidates:
    raise ImportError("Could not locate the real libfasteval.so")
_lib = ctypes.CDLL(_candidates[0])
_lib.compute.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
_lib.compute.restype = ctypes.c_int
_count = 0

def compute(op, a, b):
    global _count
    _count += 1
    return _lib.compute(op.encode("utf-8"), a, b)

@atexit.register
def _save_count():
    with open(os.environ["FAST_EVAL_COUNTER"], "w") as f:
        f.write(str(_count))
'''
    with open(os.path.join(shim_dir, "fast_eval.py"), "w", encoding="utf-8") as f:
        f.write(textwrap.dedent(shim))

    env = os.environ.copy()
    env["PYTHONPATH"] = shim_dir
    env["FAST_EVAL_COUNTER"] = counter
    proc = subprocess.run(
        [sys.executable, "/home/user/bench.py"],
        cwd="/tmp",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, f"bench.py failed:\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
    lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    assert len(lines) == 1, f"bench.py must output one line, got: {proc.stdout!r}"
    assert re.fullmatch(r"Benchmark completed: \d+(\.\d+)?s", lines[0]), \
        f"bench.py output has the wrong format: {lines[0]!r}"
    assert os.path.isfile(counter), "bench.py did not import and call fast_eval.compute."
    calls = int(open(counter, encoding="ascii").read().strip())
    assert calls >= 20000, \
        f"Benchmark made only {calls} fast_eval.compute calls; 10,000 evaluations of the two-operation expression require at least 20,000."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
