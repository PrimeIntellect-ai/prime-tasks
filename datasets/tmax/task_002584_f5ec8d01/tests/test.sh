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
import json
import math
import os
import random
import socket
import string
import subprocess
import tempfile
import time

import pytest
import requests

SO_PATH = "/app/vendor/miniscript/libminiscript.so"
MAKEFILE_PATH = "/app/vendor/miniscript/Makefile"
HTTP_URL = "http://127.0.0.1:8080/api/v1/evaluate"
AUTH_HEADERS = {"Authorization": "Bearer sec-token-999"}


def load_engine():
    lib = ctypes.CDLL(SO_PATH)
    fn = lib.evaluate_rule
    fn.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    fn.restype = ctypes.c_int
    return lib, fn


def engine_result(fn, rule, payload):
    return int(fn(rule.encode("utf-8"), payload.encode("utf-8")))


def random_text(prefix="probe", length=14):
    alphabet = string.ascii_lowercase + string.digits
    return prefix + "-" + "".join(random.SystemRandom().choice(alphabet) for _ in range(length))


def tcp_exchange(lines):
    try:
        with socket.create_connection(("127.0.0.1", 8081), timeout=3) as sock:
            sock.settimeout(3)
            sock.sendall("".join(line + "\n" for line in lines).encode("utf-8"))
            received = b""
            while received.count(b"\n") < len(lines):
                chunk = sock.recv(4096)
                if not chunk:
                    break
                received += chunk
    except (socket.error, socket.timeout) as exc:
        pytest.fail(f"Failed to connect or communicate with TCP server on 8081: {exc}")
    return received.decode("utf-8").splitlines()


def test_libminiscript_compiled():
    assert os.path.isfile(SO_PATH), f"Shared library {SO_PATH} was not compiled."
    with open(SO_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{SO_PATH} is not an ELF shared library"
    try:
        _lib, fn = load_engine()
    except (OSError, AttributeError) as exc:
        pytest.fail(f"Could not load evaluate_rule from {SO_PATH}: {exc}")
    assert engine_result(fn, "return input == 'malicious';", "malicious") == 1


def test_makefile_was_fixed():
    assert os.path.isfile(MAKEFILE_PATH), "miniscript Makefile is missing"
    text = open(MAKEFILE_PATH, "r", encoding="utf-8").read()
    assert "Wno-unnused" not in text, "The misspelled compiler flag was not fixed"
    assert "-lm" in text, "The Makefile does not link the math library with -lm"


def test_benchmark_files_exist():
    assert os.path.isfile("/app/benchmark.py"), "/app/benchmark.py is missing."
    result_path = "/app/bench_result.txt"
    assert os.path.isfile(result_path), f"{result_path} is missing."
    content = open(result_path, "r", encoding="utf-8").read().strip()
    try:
        val = float(content)
        assert val >= 0, "Benchmark result should be a positive float."
    except ValueError:
        pytest.fail(f"Contents of {result_path} cannot be parsed as a float: {content}")

    try:
        tree = ast.parse(open("/app/benchmark.py", "r", encoding="utf-8").read())
    except (OSError, SyntaxError) as exc:
        pytest.fail(f"benchmark.py is not valid Python: {exc}")
    imports_ctypes = any(
        (isinstance(node, ast.Import) and any(alias.name == "ctypes" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "ctypes")
        for node in ast.walk(tree)
    )
    assert imports_ctypes, "benchmark.py must use the ctypes module"


def test_benchmark_really_executes_100000_calls():
    wrapper_source = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static unsigned long calls = 0;
static unsigned long bad_args = 0;
int evaluate_rule(const char *script, const char *input_data) {
    calls++;
    if (!script || !input_data ||
        strcmp(script, "return input == 'malicious';") != 0 ||
        strcmp(input_data, "malicious") != 0) bad_args++;
    return 1;
}
__attribute__((destructor)) static void report(void) {
    const char *path = getenv("MINISCRIPT_BENCH_AUDIT");
    if (!path) return;
    FILE *f = fopen(path, "w");
    if (f) { fprintf(f, "%lu %lu\n", calls, bad_args); fclose(f); }
}
'''
    directory = os.path.dirname(SO_PATH)
    backup = os.path.join(directory, ".libminiscript.verifier-backup.so")
    audit_file = os.path.join(tempfile.gettempdir(), f"miniscript-bench-audit-{os.getpid()}.txt")
    source_file = os.path.join(tempfile.gettempdir(), f"miniscript-bench-wrapper-{os.getpid()}.c")
    for path in (backup, audit_file, source_file):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    with open(source_file, "w", encoding="utf-8") as f:
        f.write(wrapper_source)

    os.replace(SO_PATH, backup)
    try:
        subprocess.run(
            ["gcc", "-shared", "-fPIC", "-O2", source_file, "-o", SO_PATH],
            check=True, timeout=20, capture_output=True, text=True
        )
        try:
            os.unlink("/app/bench_result.txt")
        except FileNotFoundError:
            pass
        env = os.environ.copy()
        env["MINISCRIPT_BENCH_AUDIT"] = audit_file
        completed = subprocess.run(
            ["python3", "/app/benchmark.py"], cwd="/app", env=env,
            timeout=30, capture_output=True, text=True
        )
        assert completed.returncode == 0, (
            f"benchmark.py failed when executed: stdout={completed.stdout!r}, "
            f"stderr={completed.stderr!r}"
        )
        assert os.path.isfile(audit_file), "benchmark.py did not load and call libminiscript.so"
        count, bad_args = map(int, open(audit_file, "r", encoding="utf-8").read().split())
        assert count == 100000, f"Expected exactly 100000 evaluate_rule calls, observed {count}"
        assert bad_args == 0, "Benchmark called evaluate_rule with the wrong rule or payload"
        assert os.path.isfile("/app/bench_result.txt"), "benchmark.py did not create bench_result.txt"
        content = open("/app/bench_result.txt", "r", encoding="utf-8").read().strip()
        try:
            elapsed = float(content)
        except ValueError:
            pytest.fail(f"Fresh benchmark result is not a float: {content!r}")
        assert math.isfinite(elapsed) and elapsed >= 0, "Fresh benchmark result must be a nonnegative finite float"
    finally:
        try:
            os.unlink(SO_PATH)
        except FileNotFoundError:
            pass
        if os.path.exists(backup):
            os.replace(backup, SO_PATH)
        for path in (audit_file, source_file):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def test_http_protocol_unauthorized():
    payload = {"rule": "return len(input) > 5;", "payload": "abcdef"}
    try:
        response = requests.post(HTTP_URL, json=payload, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to HTTP server on 8080: {exc}")
    assert response.status_code == 401, f"Expected 401 Unauthorized without token, got {response.status_code}"

    wrong = {"Authorization": "Bearer " + random_text("wrong")}
    response = requests.post(HTTP_URL, json=payload, headers=wrong, timeout=2)
    assert response.status_code == 401, f"Expected 401 for an incorrect token, got {response.status_code}"


def test_http_protocol_authorized():
    payload = {"rule": "return len(input) > 5;", "payload": "abcdef"}
    try:
        response = requests.post(HTTP_URL, json=payload, headers=AUTH_HEADERS, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to HTTP server on 8080: {exc}")
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "result" in data, f"Missing 'result' in JSON response: {data}"
    assert data["result"] == 1, f"Expected result to be 1, got {data['result']}"


def test_http_uses_engine_on_varied_inputs():
    _lib, fn = load_engine()
    marker = random_text("marker")
    probes = [
        ("return input == 'malicious';", "malicious"),
        ("return input == 'malicious';", marker),
        ("return input == 'admin';", "admin-" + marker),
        ("return input == 'admin';", marker),
        ("return len(input) > 5;", marker),
        ("return len(input) > 5;", marker[:3]),
        (f"return input == '{marker}';", marker),
    ]
    random.SystemRandom().shuffle(probes)
    for rule, payload in probes:
        expected = engine_result(fn, rule, payload)
        response = requests.post(
            HTTP_URL, json={"rule": rule, "payload": payload},
            headers=AUTH_HEADERS, timeout=3
        )
        assert response.status_code == 200, f"HTTP evaluation failed: {response.status_code} {response.text}"
        data = response.json()
        assert set(data) == {"result"}, f"Unexpected HTTP response object: {data}"
        assert type(data["result"]) is int, f"HTTP result is not an integer: {data}"
        assert data["result"] == expected, (
            f"HTTP result disagrees with libminiscript.so for {rule!r}, {payload!r}"
        )


def test_tcp_protocol():
    responses = tcp_exchange(["return input == 'admin';|admin"])
    assert responses == ["1"], f"Expected '1\\n' from TCP server, got {responses!r}"


def test_tcp_uses_engine_for_multiple_dynamic_lines():
    _lib, fn = load_engine()
    marker = random_text("tcp")
    probes = [
        ("return input == 'malicious';", marker),
        ("return input == 'malicious';", "prefix-malicious-" + marker),
        ("return input == 'admin';", marker),
        ("return input == 'admin';", "admin-" + marker),
        ("return len(input) > 5;", marker[:3]),
        ("return len(input) > 5;", marker),
    ]
    random.SystemRandom().shuffle(probes)
    expected = [str(engine_result(fn, rule, payload)) for rule, payload in probes]
    actual = tcp_exchange([rule + "|" + payload for rule, payload in probes])
    assert actual == expected, f"TCP results {actual!r} disagree with libminiscript.so results {expected!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
