#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import uuid
import ctypes
import subprocess
import pytest

PROJECT = "/home/user/project"
LIB_PATH = f"{PROJECT}/lib/libhistory.so"
SCRIPT_PATH = f"{PROJECT}/tests/test_ffi.py"
LOG_PATH = f"{PROJECT}/test_results.log"

def test_project_structure():
    expected_dirs = [
        "/home/user/project/src",
        "/home/user/project/include",
        "/home/user/project/lib",
        "/home/user/project/tests",
    ]
    for d in expected_dirs:
        assert os.path.isdir(d), f"Expected directory {d} is missing."

def test_moved_files():
    hpp_path = "/home/user/project/include/string_history.hpp"
    cpp_path = "/home/user/project/src/string_history.cpp"
    assert os.path.isfile(hpp_path), f"File {hpp_path} is missing."
    assert os.path.isfile(cpp_path), f"File {cpp_path} is missing."

def test_c_api_cpp_exists():
    api_path = "/home/user/project/src/c_api.cpp"
    assert os.path.isfile(api_path), f"File {api_path} is missing."
    with open(api_path, "r") as f:
        content = f.read()
    assert "History_create" in content, "c_api.cpp does not seem to contain History_create."

def test_shared_library_exists_and_exports():
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} is missing."

    try:
        lib = ctypes.CDLL(LIB_PATH)
    except Exception as e:
        pytest.fail(f"Failed to load {LIB_PATH} with ctypes: {e}")

    assert hasattr(lib, "History_create"), "libhistory.so does not export History_create"
    assert hasattr(lib, "History_destroy"), "libhistory.so does not export History_destroy"
    assert hasattr(lib, "History_add"), "libhistory.so does not export History_add"
    assert hasattr(lib, "History_get"), "libhistory.so does not export History_get"

    lib.History_create.argtypes = [ctypes.c_int]
    lib.History_create.restype = ctypes.c_void_p
    lib.History_destroy.argtypes = [ctypes.c_void_p]
    lib.History_destroy.restype = None
    lib.History_add.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.History_add.restype = None
    lib.History_get.argtypes = [ctypes.c_void_p, ctypes.c_int]
    lib.History_get.restype = ctypes.c_char_p

    # Exercise the submitted implementation on verifier-generated values and
    # derive the expected retained history independently.
    for capacity in (1, 2, 4):
        obj = lib.History_create(capacity)
        assert obj, f"History_create({capacity}) returned a null pointer"
        try:
            added = [f"value-{uuid.uuid4().hex}" for _ in range(capacity + 3)]
            for value in added:
                lib.History_add(obj, value.encode("utf-8"))

            expected = list(reversed(added[-capacity:]))
            for index, value in enumerate(expected):
                result = lib.History_get(obj, index)
                assert result is not None, f"History_get unexpectedly returned null at index {index}"
                assert result.decode("utf-8") == value

            assert lib.History_get(obj, -1) is None
            assert lib.History_get(obj, capacity) is None
            assert lib.History_get(obj, capacity + 5) is None
        finally:
            lib.History_destroy(obj)

def test_python_test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Python test script {SCRIPT_PATH} is missing."


def test_python_test_script_content():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    for required in (
        "ctypes", "libhistory.so", "History_create", "History_destroy",
        "History_add", "History_get", "apple", "banana", "cherry",
        "ALL TESTS PASSED",
    ):
        assert required in content, f"Python integration test is missing required use of {required!r}"


def test_execute_python_test_script():
    # A pre-created or fabricated stale result cannot satisfy this check.
    if os.path.exists(LOG_PATH):
        os.unlink(LOG_PATH)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd=os.path.dirname(SCRIPT_PATH),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Python integration test failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_test_results_log():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} is missing. Did the test script run successfully?"
    with open(LOG_PATH, "r") as f:
        content = f.read().strip()
    assert content == "ALL TESTS PASSED", f"Expected log file to contain 'ALL TESTS PASSED', but got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
