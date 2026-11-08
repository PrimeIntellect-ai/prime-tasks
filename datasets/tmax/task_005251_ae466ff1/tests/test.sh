#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import os
import random
import re
import runpy
import string
import subprocess
import tempfile
import time

import pytest

APP_DIR = "/home/user/app"
C_FILE = os.path.join(APP_DIR, "libverifier.c")
SO_FILE = os.path.join(APP_DIR, "libverifier.so")
PY_FILE = os.path.join(APP_DIR, "benchmark.py")
LOG_FILE = os.path.join(APP_DIR, "benchmark_results.log")


def python_reference(token, secret, iterations):
    result = 0
    token_len = len(token)
    secret_len = len(secret)
    if token_len == 0 or secret_len == 0:
        return 0
    for _ in range(iterations):
        for i in range(token_len):
            s_char = secret[i % secret_len]
            val = (token[i] ^ s_char) * (i + 1)
            result = (result + val) % 1000003
    return result


def load_library(path):
    try:
        lib = ctypes.CDLL(path)
    except Exception as exc:
        pytest.fail(f"Failed to load shared library {path}: {exc}")
    try:
        lib.verify_token.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
        lib.verify_token.restype = ctypes.c_longlong
    except AttributeError:
        pytest.fail("Function 'verify_token' not found in the shared library.")
    return lib


def runtime_cases():
    rng = random.SystemRandom()
    alphabet = (string.ascii_letters + string.digits + "_-!@#$%^&*()[]{}").encode("ascii")
    cases = [
        (b"abc123xyz890", b"super_secure_secret", 10000),
        (b"a", b"b", 1),
        (b"different-length-token", b"xy", 37),
        (b"repeat", b"longer-secret-value", 173),
    ]
    for _ in range(16):
        token = bytes(rng.choice(alphabet) for _ in range(rng.randint(1, 35)))
        secret = bytes(rng.choice(alphabet) for _ in range(rng.randint(1, 27)))
        iterations = rng.randint(1, 1200)
        cases.append((token, secret, iterations))
    return cases


def test_files_exist():
    """Verify that all required files have been created."""
    assert os.path.exists(APP_DIR), f"Directory {APP_DIR} does not exist."
    assert os.path.isfile(C_FILE), f"C source file {C_FILE} does not exist."
    assert os.path.isfile(SO_FILE), f"Shared library {SO_FILE} does not exist."
    assert os.path.isfile(PY_FILE), f"Python script {PY_FILE} does not exist."
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} does not exist."
    with open(SO_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{SO_FILE} is not an ELF shared library"


def test_log_file_content():
    """Preserve the original assertion about the generated benchmark log."""
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} missing."
    with open(LOG_FILE, "r") as f:
        content = f.read()
    expected_str = "Result Match: True | C_Faster: True"
    assert expected_str in content, (
        f"Log file does not contain the expected string: '{expected_str}'. Found: {content}"
    )


def test_c_library_correctness():
    """Preserve the original fixed correctness assertion."""
    assert os.path.isfile(SO_FILE), f"Shared library {SO_FILE} missing."
    lib = load_library(SO_FILE)
    token = b"test_token"
    secret = b"my_secret"
    iterations = 500
    try:
        result = lib.verify_token(token, secret, iterations)
    except Exception as exc:
        pytest.fail(f"Error calling verify_token from shared library: {exc}")
    expected = python_reference(token, secret, iterations)
    assert result == expected, f"C library returned {result}, but expected {expected}"


def test_c_library_edge_cases():
    """Preserve the original edge-case assertions."""
    assert os.path.isfile(SO_FILE), f"Shared library {SO_FILE} missing."
    lib = load_library(SO_FILE)
    assert lib.verify_token(b"", b"secret", 10) == 0, "Expected 0 for empty token"
    assert lib.verify_token(b"token", b"", 10) == 0, "Expected 0 for empty secret"
    assert lib.verify_token(b"token", b"secret", 0) == 0, "Expected 0 for 0 iterations"


def test_submitted_and_rebuilt_c_libraries_on_runtime_inputs():
    """Exercise both the submitted binary and a fresh build of its C source."""
    submitted = load_library(SO_FILE)
    with tempfile.TemporaryDirectory() as td:
        rebuilt_path = os.path.join(td, "libverifier_rebuilt.so")
        proc = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-O2", C_FILE, "-o", rebuilt_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert proc.returncode == 0, f"C source did not compile:\n{proc.stderr}"
        rebuilt = load_library(rebuilt_path)

        for token, secret, iterations in runtime_cases():
            expected = python_reference(token, secret, iterations)
            assert submitted.verify_token(token, secret, iterations) == expected
            assert rebuilt.verify_token(token, secret, iterations) == expected


def test_benchmark_source_and_python_implementation():
    """Check that benchmark.py contains and uses the requested implementation pieces."""
    with open(PY_FILE, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=PY_FILE)

    assert any(isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == "verify_token"
               for n in ast.walk(tree)), "benchmark.py lacks a pure-Python verify_token function"
    assert any(isinstance(n, ast.Assert) for n in ast.walk(tree)), (
        "benchmark.py must assert that the Python and C results match"
    )
    assert any(isinstance(n, ast.Call) and (
        (isinstance(n.func, ast.Attribute) and n.func.attr == "CDLL") or
        (isinstance(n.func, ast.Name) and n.func.id == "CDLL")
    ) for n in ast.walk(tree)), "benchmark.py does not load a library through ctypes.CDLL"

    constants = {n.value for n in ast.walk(tree) if isinstance(n, ast.Constant)}
    assert "abc123xyz890" in constants
    assert "super_secure_secret" in constants
    assert 10000 in constants

    namespace = runpy.run_path(PY_FILE, run_name="__verifier_import__")
    py_verify = namespace.get("verify_token")
    assert callable(py_verify), "benchmark.py does not expose its Python verify_token implementation"

    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + "_-!@#"
    for _ in range(10):
        token = "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 25)))
        secret = "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 20)))
        iterations = rng.randint(1, 300)
        expected = python_reference(token.encode("ascii"), secret.encode("ascii"), iterations)
        assert py_verify(token, secret, iterations) == expected
    assert py_verify("", "secret", 10) == 0
    assert py_verify("token", "", 10) == 0
    assert py_verify("token", "secret", 0) == 0


def test_execute_benchmark_and_validate_fresh_log():
    """Run benchmark.py instead of trusting a prewritten result file."""
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)
    started = time.time()
    proc = subprocess.run(
        ["python3", PY_FILE],
        cwd=APP_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert proc.returncode == 0, (
        f"benchmark.py failed with exit code {proc.returncode}\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    assert os.path.isfile(LOG_FILE), "benchmark.py did not generate benchmark_results.log"
    assert os.path.getmtime(LOG_FILE) >= started - 1, "benchmark log was not freshly generated"

    with open(LOG_FILE, "r", encoding="utf-8") as f:
        content = f.read().strip()
    expected_str = "Result Match: True | C_Faster: True"
    assert expected_str in content, (
        f"Log file does not contain the expected string: '{expected_str}'. Found: {content}"
    )
    pattern = re.compile(
        r"Result Match: True \| C_Faster: True \| "
        r"Python Time: ([0-9]+\.[0-9]{4})s \| C Time: ([0-9]+\.[0-9]{4})s"
    )
    match = pattern.fullmatch(content)
    assert match, f"Benchmark log does not have the required exact format: {content!r}"
    python_time, c_time = map(float, match.groups())
    assert python_time > c_time, "Logged timings do not show the C implementation as faster"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
