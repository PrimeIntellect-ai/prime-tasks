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
import ast
import ctypes
import os
import secrets
import socket
import subprocess
import time

import pytest
import requests

LIBDIR = "/app/vendor/libexpr"
LIBPATH = os.path.join(LIBDIR, "libexpr.so")
TEST_FILE = "/home/user/test_expr.py"


def wait_for_port(url, timeout=8):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get(url, timeout=1)
            return True
        except requests.exceptions.RequestException:
            time.sleep(0.25)
    return False


def request_eval(expr):
    try:
        return requests.get(
            "http://127.0.0.1:8080/eval",
            params={"expr": expr},
            timeout=3,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the HTTP service: {exc}")


def assert_json_response(response, expected):
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    assert response.headers.get("Content-Type", "").lower().startswith("application/json"), response.headers
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert data == expected, f"Expected {expected}, got {data}"


def test_makefile_clean_build_and_shared_library_built():
    clean = subprocess.run(["make", "clean"], cwd=LIBDIR, text=True, capture_output=True, timeout=15)
    assert clean.returncode == 0, clean.stdout + clean.stderr
    build = subprocess.run(["make"], cwd=LIBDIR, text=True, capture_output=True, timeout=20)
    assert build.returncode == 0, "make failed (the dependency loop may remain):\n" + build.stdout + build.stderr
    assert os.path.isfile(LIBPATH), f"Shared library {LIBPATH} was not built. Fix the Makefile."


def test_shared_library_directly_on_varied_and_long_inputs():
    # Exercise the library in a child process so a memory-safety crash becomes a
    # normal failed assertion rather than preventing the verifier from recording a reward.
    code = r'''
import ctypes
import random
import secrets

path = "/app/vendor/libexpr/libexpr.so"
lib = ctypes.CDLL(path)
evaluate = lib.evaluate_expression
evaluate.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
evaluate.restype = ctypes.c_int

def call(value):
    out = ctypes.c_int(0x13572468)
    rc = evaluate(value.encode("utf-8"), ctypes.byref(out))
    return rc, out.value

rng = random.Random(secrets.randbits(128))
for _ in range(150):
    a = rng.randint(-1000000, 1000000)
    b = rng.randint(-1000000, 1000000)
    op = rng.choice(["+", "-"])
    rc, result = call(f"{a}{op}{b}")
    expected = a + b if op == "+" else a - b
    assert (rc, result) == (0, expected), (a, op, b, rc, result, expected)

for length in [1, 15, 16, 17, 31, 64, 127, 200, 511, 1023, 1024]:
    rc, _ = call("x" * length)
    assert rc == -1, (length, rc)

# Exactly 1024 characters, while still being a valid expression.
rc, result = call(" " * 1021 + "1+2")
assert (rc, result) == (0, 3), (rc, result)

for bad in ["", "abc", "1*2", "+", "--", "not an expression"]:
    rc, _ = call(bad)
    assert rc == -1, (bad, rc)
'''
    proc = subprocess.run(["python3", "-c", code], text=True, capture_output=True, timeout=30)
    assert proc.returncode == 0, "Direct libexpr exercise failed or crashed:\n" + proc.stdout + proc.stderr


def test_hypothesis_test_file_exists_and_contains_keywords():
    assert os.path.isfile(TEST_FILE), f"Test file {TEST_FILE} is missing."
    with open(TEST_FILE, "r", encoding="utf-8") as handle:
        content = handle.read()

    # Preserve the original assertions.
    assert "hypothesis" in content, f"Keyword 'hypothesis' not found in {TEST_FILE}"
    assert "strategies.text" in content or "text(" in content, \
        f"Keyword 'strategies.text' (or similar) not found in {TEST_FILE}"

    tree = ast.parse(content, filename=TEST_FILE)
    has_given = False
    has_text_strategy = False
    has_cdll = False
    has_evaluate_symbol = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            name = None
            if isinstance(node.func, ast.Name):
                name = node.func.id
            elif isinstance(node.func, ast.Attribute):
                name = node.func.attr
            has_given |= name == "given"
            has_text_strategy |= name == "text"
            has_cdll |= name == "CDLL"
        if isinstance(node, ast.Attribute) and node.attr == "evaluate_expression":
            has_evaluate_symbol = True
        if isinstance(node, ast.Constant) and node.value == "evaluate_expression":
            has_evaluate_symbol = True

    assert has_given, "The property test must use Hypothesis @given(...)"
    assert has_text_strategy, "The property test must generate strings with strategies.text()"
    assert has_cdll, "The property test must load libexpr.so using ctypes.CDLL"
    assert has_evaluate_symbol, "The property test must access evaluate_expression"


def test_hypothesis_property_test_runs():
    proc = subprocess.run(
        ["python3", "-m", "pytest", "-q", TEST_FILE],
        text=True,
        capture_output=True,
        timeout=45,
    )
    assert proc.returncode == 0, "Property-based test failed or crashed:\n" + proc.stdout + proc.stderr


def test_service_eval_addition():
    assert wait_for_port("http://127.0.0.1:8080/"), "HTTP service did not start on port 8080"
    response = request_eval("20+22")
    assert_json_response(response, {"result": 42})


def test_service_eval_subtraction():
    response = request_eval("100-50")
    assert_json_response(response, {"result": 50})


def test_service_eval_buffer_overflow_protection():
    response = request_eval("9" * 200)
    assert_json_response(response, {"error": "Invalid"})


def test_service_varied_unpredictable_expressions():
    rng = secrets.SystemRandom()
    for _ in range(30):
        a = rng.randint(-1000000, 1000000)
        b = rng.randint(-1000000, 1000000)
        op = rng.choice(["+", "-"])
        expected = a + b if op == "+" else a - b
        assert_json_response(request_eval(f"{a}{op}{b}"), {"result": expected})

    for length in [17, 33, 79, 257, 700, 1024]:
        value = "q" * length
        assert_json_response(request_eval(value), {"error": "Invalid"})

    # Verify URL decoding and safe handling at the required maximum length.
    expr = " " * 1021 + "1+2"
    assert_json_response(request_eval(expr), {"result": 3})


def test_service_process_has_loaded_libexpr():
    # Locate the process holding the listening socket for 127.0.0.1:8080 and
    # verify that the HTTP implementation actually loaded the C library.
    listen_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as handle:
                lines = handle.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                listen_inodes.add(fields[9])

    assert listen_inodes, "No process is listening on port 8080"
    matching_pids = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in listen_inodes:
                    matching_pids.add(pid)
        except OSError:
            continue

    loaded = False
    for pid in matching_pids:
        try:
            with open(f"/proc/{pid}/maps", "r", encoding="utf-8", errors="replace") as handle:
                if "/app/vendor/libexpr/libexpr.so" in handle.read():
                    loaded = True
                    break
        except OSError:
            pass
    assert loaded, "The HTTP service process has not loaded /app/vendor/libexpr/libexpr.so"


def test_only_documented_route_is_exposed():
    response = requests.get("http://127.0.0.1:8080/definitely-not-eval", timeout=3)
    assert response.status_code != 200, "Unexpected endpoint was exposed by the service"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
