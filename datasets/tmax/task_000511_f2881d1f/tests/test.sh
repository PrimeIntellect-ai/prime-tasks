#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import hashlib
import importlib
import os
import re
import subprocess
import sys
from unittest import mock

import pytest

RUST_DIR = "/home/user/rust_data_ext"
PROCESSOR_DIR = "/home/user/python_processor"
SO_PATH = os.path.join(PROCESSOR_DIR, "libdataparser.so")
TEST_PATH = os.path.join(PROCESSOR_DIR, "tests/test_processor.py")
LOG_PATH = "/home/user/test_results.log"


def _sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.digest()


def test_shared_library_compiled():
    assert os.path.isfile(SO_PATH), f"Shared library {SO_PATH} does not exist. Did you compile and copy it?"
    with open(SO_PATH, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"{SO_PATH} is not a valid ELF shared library."

    result = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=RUST_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, "cargo build --release failed:\n" + result.stdout

    built_library = os.path.join(RUST_DIR, "target/release/librust_data_ext.so")
    assert os.path.isfile(built_library), f"Cargo did not produce {built_library}."
    assert _sha256(SO_PATH) == _sha256(built_library), \
        "libdataparser.so is not the shared library produced by cargo build --release."


def test_shared_library_behavior():
    library = ctypes.CDLL(SO_PATH)
    function = library.normalize_and_sum
    function.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_size_t]
    function.restype = ctypes.c_double

    for original in ([10.0, 20.0, 30.0, 40.0, 50.0], [3.0, 1.0, 6.0, 2.0]):
        array_type = ctypes.c_double * len(original)
        values = array_type(*original)
        returned = function(values, len(original))
        expected_max = max(original)
        assert returned == pytest.approx(sum(original))
        assert list(values) == pytest.approx([value / expected_max for value in original])

    assert function(None, 0) == pytest.approx(0.0)


def test_wrapper_abi_fixed():
    wrapper_path = os.path.join(PROCESSOR_DIR, "wrapper.py")
    assert os.path.isfile(wrapper_path), f"File {wrapper_path} does not exist."
    with open(wrapper_path, "r") as f:
        content = f.read()

    assert "ctypes.c_double" in content, "wrapper.py must use ctypes.c_double for f64."
    assert "ctypes.c_size_t" in content, "wrapper.py must use ctypes.c_size_t for usize."
    assert "ctypes.c_float" not in content, "wrapper.py should not contain ctypes.c_float."
    assert "ctypes.c_int" not in content, "wrapper.py should not contain ctypes.c_int."

    sys.path.insert(0, PROCESSOR_DIR)
    try:
        sys.modules.pop("wrapper", None)
        wrapper = importlib.import_module("wrapper")
        function = wrapper.lib.normalize_and_sum
        assert function.argtypes == [ctypes.POINTER(ctypes.c_double), ctypes.c_size_t]
        assert function.restype is ctypes.c_double

        data = [8.0, 2.0, 4.0]
        returned = wrapper.normalize_and_sum(data)
        assert returned == pytest.approx(14.0)
        assert data == pytest.approx([1.0, 0.25, 0.5])
    finally:
        if sys.path and sys.path[0] == PROCESSOR_DIR:
            sys.path.pop(0)


def test_app_process_data_behavior_and_reporting():
    sys.path.insert(0, PROCESSOR_DIR)
    try:
        sys.modules.pop("app", None)
        app = importlib.import_module("app")
        sample_data = [10.0, 20.0, 30.0, 40.0, 50.0]
        with mock.patch.object(app, "report_analytics") as reporter:
            returned = app.process_data(sample_data)
        assert returned == pytest.approx(150.0)
        assert sample_data == pytest.approx([0.2, 0.4, 0.6, 0.8, 1.0])
        reporter.assert_called_once_with(150.0)
    finally:
        if sys.path and sys.path[0] == PROCESSOR_DIR:
            sys.path.pop(0)


def test_pytest_file_exists_and_contains_requirements():
    assert os.path.isfile(TEST_PATH), f"Test file {TEST_PATH} does not exist."
    with open(TEST_PATH, "r") as f:
        content = f.read()

    assert "def test_process_and_report" in content, "Test function 'test_process_and_report' is missing."
    assert "150.0" in content, "The test should assert the sum is 150.0."
    assert "patch" in content or "mocker" in content, "The test must use patch or mocker to mock report_analytics."

    tree = ast.parse(content, filename=TEST_PATH)
    functions = {node.name: node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))}
    assert "sample_data" in functions, "A sample_data fixture is missing."
    fixture = functions["sample_data"]
    assert any(
        (isinstance(dec, ast.Name) and dec.id == "fixture") or
        (isinstance(dec, ast.Attribute) and dec.attr == "fixture") or
        (isinstance(dec, ast.Call) and (
            (isinstance(dec.func, ast.Name) and dec.func.id == "fixture") or
            (isinstance(dec.func, ast.Attribute) and dec.func.attr == "fixture")
        ))
        for dec in fixture.decorator_list
    ), "sample_data must be decorated as a pytest fixture."
    returns = [node for node in ast.walk(fixture) if isinstance(node, ast.Return)]
    assert returns, "sample_data must return the required list."
    assert ast.literal_eval(returns[0].value) == [10.0, 20.0, 30.0, 40.0, 50.0]

    test_function = functions.get("test_process_and_report")
    assert test_function is not None
    assert "sample_data" in [arg.arg for arg in test_function.args.args], \
        "test_process_and_report must use the sample_data fixture."
    called_names = {
        node.func.id if isinstance(node.func, ast.Name) else node.func.attr
        for node in ast.walk(test_function)
        if isinstance(node, ast.Call) and isinstance(node.func, (ast.Name, ast.Attribute))
    }
    assert "process_data" in called_names, "test_process_and_report must call process_data."


def test_pytest_log_exists_and_passed():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist. Did you run the pytest command and redirect output?"
    with open(LOG_PATH, "r") as f:
        content = f.read()

    assert re.search(r"1 passed", content) or re.search(r"passed.*1", content), "The pytest log does not indicate that 1 test passed."
    assert "FAILED" not in content, "The pytest log contains failures."


def test_submitted_pytest_suite_actually_passes():
    result = subprocess.run(
        [sys.executable, "-m", "pytest", TEST_PATH, "-v"],
        cwd=PROCESSOR_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=120,
    )
    with open(LOG_PATH, "w") as handle:
        handle.write(result.stdout)
    assert result.returncode == 0, "The requested pytest suite failed:\n" + result.stdout
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
