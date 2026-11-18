#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import random
import runpy
import subprocess
import sys
import pytest

PROJECT_DIR = "/home/user/project"

@pytest.fixture(scope="session", autouse=True)
def rebuild_and_run_tests():
    lib_path = os.path.join(PROJECT_DIR, "libmathops.so")
    log_path = os.path.join(PROJECT_DIR, "test_results.log")
    for path in (lib_path, log_path):
        if os.path.lexists(path):
            os.remove(path)

    subprocess.run(
        ["make", "-B", "libmathops.so"],
        cwd=PROJECT_DIR,
        check=True,
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert os.path.isfile(lib_path), "make did not produce libmathops.so"

    subprocess.run(
        [sys.executable, os.path.join(PROJECT_DIR, "test_mathops.py")],
        cwd=PROJECT_DIR,
        check=True,
        text=True,
        capture_output=True,
        timeout=120,
    )


def test_test_results_log_exists_and_passed():
    log_path = os.path.join(PROJECT_DIR, "test_results.log")
    assert os.path.isfile(log_path), f"File {log_path} does not exist. Did the tests run successfully?"

    with open(log_path, "r") as f:
        content = f.read()

    assert "PASSED" in content, f"Expected 'PASSED' in {log_path}, but got: {content}"


def test_shared_library_built_correctly():
    lib_path = os.path.join(PROJECT_DIR, "libmathops.so")
    assert os.path.isfile(lib_path), f"Shared library {lib_path} does not exist."

    file_output = subprocess.check_output(["file", lib_path], text=True)
    assert "shared object" in file_output, f"{lib_path} is not a shared object. Output: {file_output}"

    ldd_output = subprocess.check_output(["ldd", lib_path], text=True)
    assert "libm.so" in ldd_output, f"{lib_path} does not link against libm.so. Did you forget -lm?"


def test_makefile_fixed():
    makefile_path = os.path.join(PROJECT_DIR, "Makefile")
    assert os.path.isfile(makefile_path), f"Makefile {makefile_path} does not exist."

    with open(makefile_path, "r") as f:
        content = f.read()

    assert "-shared" in content, "Makefile is missing the '-shared' flag."
    assert "-fPIC" in content, "Makefile is missing the '-fPIC' flag."
    assert "-lm" in content, "Makefile is missing the '-lm' flag to link the math library."


def test_python_script_fixed():
    py_path = os.path.join(PROJECT_DIR, "test_mathops.py")
    assert os.path.isfile(py_path), f"Python script {py_path} does not exist."

    with open(py_path, "r") as f:
        content = f.read()

    assert "argtypes" in content, "test_mathops.py is missing 'argtypes' definition for the C function."
    assert "restype" in content, "test_mathops.py is missing 'restype' definition for the C function."
    assert "c_double" in content, "test_mathops.py is missing ctypes.c_double in argtypes."
    assert "c_int" in content, "test_mathops.py is missing ctypes.c_int in restype."


def test_python_bindings_are_really_configured():
    py_path = os.path.join(PROJECT_DIR, "test_mathops.py")
    namespace = runpy.run_path(py_path, run_name="verifier_import")
    lib = namespace.get("lib")
    assert isinstance(lib, ctypes.CDLL), "test_mathops.py must load the shared library with ctypes.CDLL"
    function = lib.is_inside_circle
    assert function.argtypes == [ctypes.c_double, ctypes.c_double, ctypes.c_double]
    assert function.restype is ctypes.c_int


def test_is_inside_circle_behavior():
    lib_path = os.path.join(PROJECT_DIR, "libmathops.so")
    lib = ctypes.CDLL(lib_path)
    function = lib.is_inside_circle
    function.argtypes = [ctypes.c_double, ctypes.c_double, ctypes.c_double]
    function.restype = ctypes.c_int

    cases = [
        (0.0, 0.0, 1.0),
        (3.0, 4.0, 5.0),
        (3.0, 4.0, 5.000001),
        (0.0, 0.0, 0.0),
        (1.0, 1.0, -2.0),
        (-100.0, 100.0, 150.0),
    ]
    rng = random.SystemRandom()
    for _ in range(100):
        cases.append((
            rng.uniform(-1000.0, 1000.0),
            rng.uniform(-1000.0, 1000.0),
            rng.uniform(-50.0, 1500.0),
        ))

    for x, y, radius in cases:
        expected = 1 if math.hypot(x, y) < radius else 0
        actual = function(x, y, radius)
        assert actual == expected, (
            f"is_inside_circle({x}, {y}, {radius}) returned {actual}; expected {expected}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
