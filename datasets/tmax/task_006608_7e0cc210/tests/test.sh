#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import subprocess
import pytest

PROJECT = "/home/user/project"
APP_PATH = f"{PROJECT}/bin/app"
LIB_PATH = f"{PROJECT}/lib/libmath.so"


def expected_result(operation, a, b):
    if operation == "add":
        return a + b
    if operation == "sub":
        return a - b
    if operation == "mul":
        return a * b
    pytest.fail(f"Unsupported operation in config.json: {operation!r}")


def configured_operation():
    with open(f"{PROJECT}/config.json", "r") as f:
        config = json.load(f)
    operation = config.get("operation")
    assert operation in {"add", "sub", "mul"}, f"Invalid operation: {operation!r}"
    return operation


def test_output_txt():
    output_path = f"{PROJECT}/output.txt"
    assert os.path.isfile(output_path), f"File {output_path} does not exist"

    with open(output_path, "r") as f:
        content = f.read().strip()

    assert content == "35", f"Expected output.txt to contain '35', but found '{content}'"


def test_libmath_exists():
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} does not exist"


def test_app_exists():
    assert os.path.isfile(APP_PATH), f"Executable {APP_PATH} does not exist"
    assert os.access(APP_PATH, os.X_OK), f"File {APP_PATH} is not executable"


def test_app_rpath_linking():
    try:
        result = subprocess.run(["ldd", APP_PATH], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Running ldd on {APP_PATH} failed: {e.stderr}")

    output = result.stdout
    found = False
    for line in output.splitlines():
        if "libmath.so" in line and "=>" in line:
            parts = line.split("=>")
            if len(parts) == 2:
                resolved_path = parts[1].split()[0]
                if "project/lib/libmath.so" in resolved_path:
                    found = True
                    break

    assert found, "libmath.so is not properly linked with rpath or cannot be found by ldd"


def test_library_do_math_on_varied_inputs():
    operation = configured_operation()
    try:
        library = ctypes.CDLL(LIB_PATH)
        do_math = library.do_math
    except (OSError, AttributeError) as e:
        pytest.fail(f"Could not load do_math from {LIB_PATH}: {e}")

    do_math.argtypes = [ctypes.c_int, ctypes.c_int]
    do_math.restype = ctypes.c_int

    cases = [(50, 15), (9, 4), (-7, 3), (6, -5), (0, 11)]
    for a, b in cases:
        actual = do_math(a, b)
        expected = expected_result(operation, a, b)
        assert actual == expected, f"do_math({a}, {b}) returned {actual}, expected {expected}"


def test_app_on_varied_inputs_without_library_path_environment():
    operation = configured_operation()
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)

    cases = [(9, 4), (-7, 3), (6, -5), (0, 11)]
    for a, b in cases:
        result = subprocess.run(
            [APP_PATH, str(a), str(b)],
            capture_output=True,
            text=True,
            env=env,
            timeout=5,
        )
        assert result.returncode == 0, (
            f"app failed for inputs {a}, {b} with exit code {result.returncode}: {result.stderr}"
        )
        expected = str(expected_result(operation, a, b))
        assert result.stdout.strip() == expected, (
            f"app {a} {b} printed {result.stdout.strip()!r}, expected {expected!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
