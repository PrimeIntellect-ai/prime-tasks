#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import subprocess
import ctypes
import secrets
import pytest

PROJECT_DIR = "/home/user/math_project"
SO_PATH = os.path.join(PROJECT_DIR, "libfastmath.so")


def compute_truth(n):
    """Derive the expected recurrence relation value natively in Python."""
    if n == 0:
        return 0
    if n == 1:
        return 1
    a, b = 0, 1
    for _ in range(2, n + 1):
        a, b = b, (3 * b + 2 * a) % 998244353
    return b


def test_build_and_test_exists_and_executable():
    path = "/home/user/math_project/build_and_test.sh"
    assert os.path.isfile(path), f"{path} is missing. Did you create the bash script?"
    assert os.access(path, os.X_OK), f"{path} is not executable. Check file permissions."


def test_pipeline_execution():
    script_path = "/home/user/math_project/build_and_test.sh"
    log_path = "/home/user/pipeline_result.log"

    # Ensure the pipeline must create fresh build and log artifacts.
    for path in (SO_PATH, log_path):
        if os.path.lexists(path):
            os.remove(path)

    # Run from a different directory to ensure paths are handled correctly in the wrapper and script.
    result = subprocess.run(["bash", script_path], cwd="/home/user", capture_output=True, text=True)
    assert result.returncode == 0, f"build_and_test.sh failed with return code {result.returncode}.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"

    assert os.path.isfile(log_path), f"{log_path} was not created by the pipeline script."

    with open(log_path, "r") as f:
        log_content = f.read()

    expected_val = compute_truth(1000)
    expected_str = f"PIPELINE_OK: SEQ_1000={expected_val}"
    assert expected_str in log_content, f"Expected '{expected_str}' in {log_path}, got: {log_content}"


def test_math_wrapper_ffi():
    # Ensure the shared library exists before trying to import.
    assert os.path.isfile(SO_PATH), f"{SO_PATH} is missing. Compilation step may have failed."
    with open(SO_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{SO_PATH} is not an ELF shared library"

    old_cwd = os.getcwd()
    sys.path.insert(0, PROJECT_DIR)
    sys.modules.pop("math_wrapper", None)
    try:
        # Import outside the project directory to verify location-independent loading.
        os.chdir("/tmp")
        import math_wrapper
        assert isinstance(math_wrapper.lib, ctypes.CDLL), "math_wrapper.lib must be a ctypes.CDLL instance"
        assert os.path.realpath(os.fspath(math_wrapper.lib._name)) == os.path.realpath(SO_PATH), \
            f"math_wrapper loaded the wrong library: {math_wrapper.lib._name}"

        func = math_wrapper.lib.compute_seq
        assert isinstance(func, ctypes._CFuncPtr), "compute_seq must be a function loaded from the shared library"
        assert hasattr(func, "argtypes") and func.argtypes is not None, "argtypes not set on compute_seq in math_wrapper.py"
        assert hasattr(func, "restype") and func.restype is not None, "restype not set on compute_seq in math_wrapper.py"

        assert func.argtypes == [ctypes.c_uint32], f"argtypes should be [ctypes.c_uint32], got {func.argtypes}"
        assert func.restype == ctypes.c_uint64, f"restype should be ctypes.c_uint64, got {func.restype}"

        # Preserve the original fixed assertion.
        expected_1000 = compute_truth(1000)
        actual_1000 = math_wrapper.get_seq(1000)
        assert actual_1000 == expected_1000, f"get_seq(1000) returned incorrect value. Expected {expected_1000}, got {actual_1000}"

        # Exercise both the actual exported C function and the wrapper on runtime-selected
        # inputs, so a fixed-value stub cannot satisfy the verifier.
        challenge_inputs = [0, 1, 2, 3]
        challenge_inputs.extend(2 + secrets.randbelow(200000) for _ in range(10))

        direct_lib = ctypes.CDLL(SO_PATH)
        direct_func = direct_lib.compute_seq
        direct_func.argtypes = [ctypes.c_uint32]
        direct_func.restype = ctypes.c_uint64

        for n in challenge_inputs:
            expected = compute_truth(n)
            direct_actual = direct_func(n)
            wrapper_actual = math_wrapper.get_seq(n)
            assert direct_actual == expected, \
                f"C compute_seq({n}) returned {direct_actual}, expected {expected}"
            assert wrapper_actual == expected, \
                f"get_seq({n}) returned {wrapper_actual}, expected {expected}"
    finally:
        os.chdir(old_cwd)
        sys.path.pop(0)
        sys.modules.pop("math_wrapper", None)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
