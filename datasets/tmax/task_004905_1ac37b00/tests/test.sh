#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import subprocess
from pathlib import Path

import pytest

LIB_V1 = "/home/user/lib/libdata.so.1"
LIB_V2 = "/home/user/lib/libdata.so.2"
APP = "/home/user/app.py"


def run_app(library, input_string):
    proc = subprocess.run(
        ["python3", APP, str(library), input_string],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=True,
    )
    return proc.stdout


def load_and_get_version(path, required_symbol):
    try:
        library = ctypes.CDLL(path)
    except OSError as exc:
        pytest.fail(f"Not a loadable shared library: {path}: {exc}")

    assert hasattr(library, "get_version"), f"Missing get_version in {path}"
    assert hasattr(library, required_symbol), f"Missing {required_symbol} in {path}"
    library.get_version.argtypes = []
    library.get_version.restype = ctypes.c_char_p
    raw_version = library.get_version()
    assert raw_version is not None, f"get_version returned NULL for {path}"
    return raw_version.decode("ascii")


def test_shared_libraries_exist():
    lib_v1 = LIB_V1
    lib_v2 = LIB_V2

    assert os.path.exists(lib_v1), f"Shared library missing: {lib_v1}"
    assert os.path.isfile(lib_v1), f"Expected a file at {lib_v1}"

    assert os.path.exists(lib_v2), f"Shared library missing: {lib_v2}"
    assert os.path.isfile(lib_v2), f"Expected a file at {lib_v2}"

    version_v1 = load_and_get_version(lib_v1, "encode_data")
    version_v2 = load_and_get_version(lib_v2, "encode_data_wide")
    assert version_v1 == "1.8.4"
    assert version_v2 == "2.1.0"


def test_app_script_exists():
    app_path = APP
    assert os.path.exists(app_path), f"Python script missing: {app_path}"
    assert os.path.isfile(app_path), f"Expected a file at {app_path}"


def test_result_v1_contents():
    result_path = "/home/user/result_v1.txt"
    assert os.path.exists(result_path), f"Result file missing: {result_path}"

    with open(result_path, "r") as f:
        content = f.read()

    expected = "UftuTusjoh234\n"
    assert content == expected, f"Incorrect content in {result_path}. Expected {repr(expected)}, got {repr(content)}"


def test_result_v2_contents():
    result_path = "/home/user/result_v2.txt"
    assert os.path.exists(result_path), f"Result file missing: {result_path}"

    with open(result_path, "r") as f:
        content = f.read()

    expected = "VguvUvtkpi345\n"
    assert content == expected, f"Incorrect content in {result_path}. Expected {repr(expected)}, got {repr(content)}"


def test_app_executes_both_built_libraries():
    token = "DynamicCheck" + secrets.token_hex(6)
    expected_v1 = "".join(chr(ord(ch) + 1) for ch in token) + "\n"
    expected_v2 = "".join(chr(ord(ch) + 2) for ch in token) + "\n"
    assert run_app(LIB_V1, token) == expected_v1
    assert run_app(LIB_V2, token) == expected_v2


def compile_probe(source, output):
    source_path = output.with_suffix(".c")
    source_path.write_text(source)
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", str(output), str(source_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        check=True,
    )


def test_app_dynamically_uses_requested_abi(tmp_path):
    shift_v1 = 3 + secrets.randbelow(7)
    shift_v2 = 10 + secrets.randbelow(7)
    probe_v1 = tmp_path / "probe_one.so"
    probe_v2 = tmp_path / "probe_two.so"

    compile_probe(
        f'''#include <stddef.h>
const char* get_version(void) {{ return "1.99.7"; }}
void encode_data(const char* input, char* output) {{
    size_t i = 0;
    while (input[i]) {{ output[i] = (char)(input[i] + {shift_v1}); i++; }}
    output[i] = '\\0';
}}
''',
        probe_v1,
    )
    compile_probe(
        f'''#include <stddef.h>
#include <wchar.h>
const char* get_version(void) {{ return "2.0.0"; }}
void encode_data_wide(const wchar_t* input, wchar_t* output) {{
    size_t i = 0;
    while (input[i]) {{ output[i] = input[i] + {shift_v2}; i++; }}
    output[i] = L'\\0';
}}
''',
        probe_v2,
    )

    token = "ABCD1234"
    expected_v1 = "".join(chr(ord(ch) + shift_v1) for ch in token) + "\n"
    expected_v2 = "".join(chr(ord(ch) + shift_v2) for ch in token) + "\n"
    assert run_app(probe_v1, token) == expected_v1
    assert run_app(probe_v2, token) == expected_v2
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
