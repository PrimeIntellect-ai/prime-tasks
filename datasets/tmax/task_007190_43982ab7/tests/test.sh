#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import io
import os
import re
import runpy
import struct
import subprocess
import unittest
import pytest

SCRIPT_PATH = "/home/user/test_processor.py"
LOG_PATH = "/home/user/test_results.log"
LIB_PATH = "/home/user/lib/libdata_processor.so"


def test_test_results_log_exists():
    assert os.path.isfile(LOG_PATH), f"Log file missing at {LOG_PATH}. Did you redirect the test output?"


def test_test_results_log_content():
    if not os.path.isfile(LOG_PATH):
        pytest.fail(f"Log file missing at {LOG_PATH}")

    with open(LOG_PATH, "r") as f:
        content = f.read()

    assert "OK" in content, "Log file does not show passing tests (missing 'OK')."
    assert re.search(r"Ran\s+2\s+tests?", content), "Log is not the unittest output for the two integration tests."
    assert os.path.getmtime(LOG_PATH) >= os.path.getmtime(SCRIPT_PATH), "Test log predates the fixed Python script."


def test_python_script_execution():
    assert os.path.isfile(SCRIPT_PATH), f"Python test script missing at {SCRIPT_PATH}"

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    assert result.returncode == 0, f"Python tests failed to execute successfully. Exit code: {result.returncode}\nStderr: {result.stderr}"
    assert "OK" in result.stderr, "Output of python script does not indicate passing tests."


def test_python_script_fixed():
    if not os.path.isfile(SCRIPT_PATH):
        pytest.fail(f"Python test script missing at {SCRIPT_PATH}")

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    assert "_pack_" in content, "The Record class in the Python script does not seem to have been packed (_pack_ missing)."


def test_record_and_library_behavior_independently():
    # Load and retain trusted ctypes operations before executing agent-editable code.
    trusted_cdll = ctypes.CDLL
    trusted_structure = ctypes.Structure
    trusted_sizeof = ctypes.sizeof
    trusted_addressof = ctypes.addressof
    trusted_string_at = ctypes.string_at
    trusted_pointer = ctypes.POINTER
    trusted_byref = ctypes.byref
    expected_fields = [
        ("type", ctypes.c_uint8),
        ("value", ctypes.c_double),
        ("id", ctypes.c_uint32),
    ]
    test_case_base = unittest.TestCase
    loader_type = unittest.TestLoader
    runner_type = unittest.TextTestRunner

    c_lib = trusted_cdll(LIB_PATH)
    c_lib.get_record_size.restype = ctypes.c_int

    namespace = runpy.run_path(SCRIPT_PATH, run_name="submission_under_test")

    Record = namespace.get("Record")
    assert isinstance(Record, type), "The script does not define a Record class."
    assert Record.__bases__ == (trusted_structure,), "Record must directly inherit from ctypes.Structure."
    assert getattr(Record, "_pack_", None) == 1, "Record must use one-byte packing (_pack_ = 1)."
    assert getattr(Record, "_fields_", None) == expected_fields, "Record fields or ctypes do not match the C struct."

    c_size = c_lib.get_record_size()
    assert c_size == 13, f"Unexpected C Record size: {c_size}"
    assert trusted_sizeof(Record) == c_size, "Python Record size does not match the C ABI."
    assert [Record.type.offset, Record.value.offset, Record.id.offset] == [0, 1, 9], "Record field offsets do not match the packed C struct."

    c_lib.process_record.argtypes = [trusted_pointer(Record)]
    c_lib.process_record.restype = None
    record = Record(type=0xA5, value=-3.25, id=0x12345670)

    before = trusted_string_at(trusted_addressof(record), c_size)
    assert before[0] == 0xA5
    assert struct.unpack_from("=d", before, 1)[0] == pytest.approx(-3.25)
    assert struct.unpack_from("=I", before, 9)[0] == 0x12345670

    c_lib.process_record(trusted_byref(record))
    after = trusted_string_at(trusted_addressof(record), c_size)
    assert after[0] == 0xA5
    assert struct.unpack_from("=d", after, 1)[0] == pytest.approx(-6.5)
    assert struct.unpack_from("=I", after, 9)[0] == 0x12345671

    script_lib = namespace.get("lib")
    assert isinstance(script_lib, trusted_cdll), "The integration script did not load a C shared library with ctypes.CDLL."
    assert os.path.realpath(script_lib._name) == os.path.realpath(LIB_PATH), "The integration script loaded the wrong shared library."

    test_class = namespace.get("TestDataProcessor")
    assert isinstance(test_class, type) and issubclass(test_class, test_case_base), "TestDataProcessor must remain a unittest.TestCase."
    suite = loader_type().loadTestsFromTestCase(test_class)
    assert suite.countTestCases() == 2, "The integration script must retain both original unit tests."
    output = io.StringIO()
    result = runner_type(stream=output, verbosity=1).run(suite)
    assert result.wasSuccessful(), f"Imported integration tests failed:\n{output.getvalue()}"


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
