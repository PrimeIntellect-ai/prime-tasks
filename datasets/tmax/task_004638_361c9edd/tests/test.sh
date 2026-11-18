#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import importlib.util
import os
import re
import subprocess
import sys
import zlib


def load_wrapper():
    wrapper_path = "/home/user/checksum_wrapper.py"
    assert os.path.exists(wrapper_path), f"File not found: {wrapper_path}"

    spec = importlib.util.spec_from_file_location("checksum_wrapper", wrapper_path)
    checksum_wrapper = importlib.util.module_from_spec(spec)
    sys.modules["checksum_wrapper"] = checksum_wrapper
    try:
        spec.loader.exec_module(checksum_wrapper)
    except Exception as e:
        assert False, f"Failed to import checksum_wrapper.py: {e}"
    return checksum_wrapper


def test_result_file():
    result_path = "/home/user/result.txt"
    assert os.path.exists(result_path), f"File not found: {result_path}"

    with open(result_path, "r") as f:
        content = f.read().strip()

    expected_checksum = zlib.crc32(b"MOBILE_BUILD_PIPELINE_STABLE")
    assert content == str(expected_checksum), f"Expected result.txt to contain '{expected_checksum}', but found '{content}'"


def test_checksum_wrapper():
    checksum_wrapper = load_wrapper()
    assert hasattr(checksum_wrapper, "get_checksum"), "get_checksum function is missing from checksum_wrapper.py"
    assert hasattr(checksum_wrapper, "lib"), "checksum_wrapper.py must load libfastchk.so"
    assert isinstance(checksum_wrapper.lib, ctypes.CDLL), "lib must be a ctypes.CDLL instance"

    native_function = checksum_wrapper.lib.calculate_checksum
    expected_argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.POINTER(ctypes.c_uint)]
    assert list(native_function.argtypes or []) == expected_argtypes, \
        f"calculate_checksum.argtypes must be {expected_argtypes}, got {native_function.argtypes}"
    assert native_function.restype is ctypes.c_int, \
        f"calculate_checksum.restype must be ctypes.c_int, got {native_function.restype}"

    # Retain the original b"test" assertion and exercise many additional,
    # verifier-generated values so a fixed answer cannot pass.
    test_values = [
        b"test",
        b"",
        b"MOBILE_BUILD_PIPELINE_STABLE",
        b"contains\\x00embedded\\x00nulls",
        bytes(range(256)),
    ]
    test_values.extend(os.urandom(length) for length in (1, 2, 7, 31, 127, 513, 2049))

    for test_val in test_values:
        try:
            result = checksum_wrapper.get_checksum(test_val)
        except Exception as e:
            assert False, f"Calling get_checksum failed for an input of length {len(test_val)}: {e}. The ctypes FFI might still be buggy."
        expected = zlib.crc32(test_val)
        assert result == expected, \
            f"get_checksum returned {result} for an input of length {len(test_val)}, expected {expected}"

    # Replace the native symbol with a probe. A correct wrapper must call it,
    # pass an output pointer, check its status, and return the written c_uint.
    sentinel = 0xA1B2C3D4
    calls = []

    def ffi_probe(data, length, output):
        calls.append((data, length, output))
        assert length == len(b"ffi-routing-probe"), "Incorrect length passed to calculate_checksum"
        ctypes.cast(output, ctypes.POINTER(ctypes.c_uint))[0] = sentinel
        return 0

    replaced_module_names = []
    for name, value in list(vars(checksum_wrapper).items()):
        if value is native_function:
            replaced_module_names.append(name)
            setattr(checksum_wrapper, name, ffi_probe)

    checksum_wrapper.lib.calculate_checksum = ffi_probe
    try:
        routed_result = checksum_wrapper.get_checksum(b"ffi-routing-probe")
    finally:
        checksum_wrapper.lib.calculate_checksum = native_function
        for name in replaced_module_names:
            setattr(checksum_wrapper, name, native_function)

    assert calls, "get_checksum did not call libfastchk's calculate_checksum function"
    assert routed_result == sentinel, \
        "get_checksum did not return the unsigned integer written through the FFI output pointer"


def test_unit_test_script():
    test_script_path = "/home/user/test_checksum.py"
    assert os.path.exists(test_script_path), f"File not found: {test_script_path}"

    # Keep the original requirement that the script itself exits successfully.
    result = subprocess.run(
        [sys.executable, test_script_path],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"test_checksum.py failed with exit code {result.returncode}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

    with open(test_script_path, "r") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=test_script_path)
    except SyntaxError as e:
        assert False, f"test_checksum.py is not valid Python: {e}"

    imports_unittest = any(
        (isinstance(node, ast.Import) and any(alias.name == "unittest" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "unittest")
        for node in ast.walk(tree)
    )
    imports_get_checksum = any(
        isinstance(node, ast.ImportFrom)
        and node.module == "checksum_wrapper"
        and any(alias.name == "get_checksum" for alias in node.names)
        for node in ast.walk(tree)
    )
    has_test_case = any(
        isinstance(node, ast.ClassDef)
        and any(
            (isinstance(base, ast.Attribute) and base.attr == "TestCase")
            or (isinstance(base, ast.Name) and base.id == "TestCase")
            for base in node.bases
        )
        for node in ast.walk(tree)
    )
    has_test_method = any(
        isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test")
        for node in ast.walk(tree)
    )
    has_assertion = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr.startswith("assert")
        for node in ast.walk(tree)
    )
    has_test_literal = any(isinstance(node, ast.Constant) and node.value == b"test" for node in ast.walk(tree))
    uses_zlib_crc32 = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and isinstance(node.func.value, ast.Name)
        and node.func.value.id == "zlib"
        and node.func.attr == "crc32"
        for node in ast.walk(tree)
    )

    assert imports_unittest, "test_checksum.py must use the standard unittest module"
    assert imports_get_checksum, "test_checksum.py must import get_checksum from checksum_wrapper"
    assert has_test_case and has_test_method, "test_checksum.py must define at least one unittest test case"
    assert has_assertion, "test_checksum.py must contain a unittest assertion"
    assert has_test_literal, "test_checksum.py must test the exact byte string b'test'"
    assert uses_zlib_crc32, "test_checksum.py must use zlib.crc32 to determine the expected checksum"

    # Load and run the unittest suite independently, preventing a script that
    # merely exits zero (or defines no tests) from passing.
    runner_code = r'''
import importlib.util
import sys
import unittest
path = "/home/user/test_checksum.py"
spec = importlib.util.spec_from_file_location("submitted_checksum_test", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
suite = unittest.defaultTestLoader.loadTestsFromModule(module)
print("VERIFIER_TEST_COUNT=%d" % suite.countTestCases())
result = unittest.TextTestRunner(verbosity=2).run(suite)
sys.exit(0 if result.wasSuccessful() and suite.countTestCases() > 0 else 1)
'''
    suite_result = subprocess.run(
        [sys.executable, "-c", runner_code],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    output = suite_result.stdout + "\n" + suite_result.stderr
    count_match = re.search(r"VERIFIER_TEST_COUNT=(\d+)", output)
    assert count_match and int(count_match.group(1)) > 0, "test_checksum.py does not provide a runnable unittest test"
    assert suite_result.returncode == 0, f"The unittest suite failed.\nSTDOUT:\n{suite_result.stdout}\nSTDERR:\n{suite_result.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
