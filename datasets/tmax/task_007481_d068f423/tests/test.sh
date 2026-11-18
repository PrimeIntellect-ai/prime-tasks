#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import ctypes
import json
import os
import secrets
import subprocess
import sys
import pytest

WORKSPACE_DIR = '/home/user/workspace'
LIBPARSER_PATH = os.path.join(WORKSPACE_DIR, 'libparser.so')
PARSER_SOURCE_PATH = os.path.join(WORKSPACE_DIR, 'parser.c')
RESULT_JSON_PATH = os.path.join(WORKSPACE_DIR, 'result.json')
SOURCE_CHECK_LIB = '/tmp/parser_source_check.so'


def test_make_rebuilds_library():
    if os.path.exists(LIBPARSER_PATH):
        os.unlink(LIBPARSER_PATH)

    result = subprocess.run(
        ['make'], cwd=WORKSPACE_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    assert result.returncode == 0, f"Running make failed:\n{result.stdout}"
    assert os.path.isfile(LIBPARSER_PATH), "make did not create libparser.so"


def test_libparser_so_exists_and_is_shared():
    assert os.path.isfile(LIBPARSER_PATH), f"{LIBPARSER_PATH} does not exist. Did you run make?"

    try:
        output = subprocess.check_output(['file', LIBPARSER_PATH], text=True)
        assert "shared object" in output.lower(), f"{LIBPARSER_PATH} is not a valid shared object. Check your Makefile flags."
    except subprocess.CalledProcessError:
        pytest.fail(f"Failed to run 'file' command on {LIBPARSER_PATH}")


def invoke_parser(lib_path, payload):
    helper = r'''
import base64
import ctypes
import sys
lib = ctypes.CDLL(sys.argv[1])
lib.parse_token.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
lib.parse_token.restype = None
payload = base64.b64decode(sys.argv[2])
out = ctypes.create_string_buffer(16384)
lib.parse_token(payload, out)
sys.stdout.buffer.write(base64.b64encode(out.value))
'''
    encoded = base64.b64encode(payload.encode('ascii')).decode('ascii')
    result = subprocess.run(
        [sys.executable, '-c', helper, lib_path, encoded],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f"parse_token crashed or failed for a long token (exit {result.returncode}):\n"
        + result.stderr.decode('utf-8', errors='replace')
    )
    try:
        raw = base64.b64decode(result.stdout, validate=True)
        return json.loads(raw.decode('utf-8'))
    except Exception as exc:
        pytest.fail(f"parse_token did not return valid JSON: {exc}; output={result.stdout!r}")


def exercise_truncation(lib_path):
    nonce = secrets.token_hex(16)
    pairs = [
        ('k' + nonce + ('x' * 20000), 'v' + nonce[::-1] + ('y' * 20000)),
        ('e' + secrets.token_hex(7), 'f' + secrets.token_hex(7)),
        ('sixteen_chars_key', 'sixteen_chars_val'),
        ('tail_' + secrets.token_hex(4), 'done_' + secrets.token_hex(4)),
    ]
    payload = ''.join(f'{key}:{value};' for key, value in pairs)
    expected = {key[:15]: value[:15] for key, value in pairs}
    actual = invoke_parser(lib_path, payload)
    assert actual == expected, f"Expected safely truncated pairs {expected!r}, got {actual!r}"


def test_built_library_handles_dynamic_long_inputs():
    exercise_truncation(LIBPARSER_PATH)


def test_parser_source_itself_has_safe_truncation():
    assert os.path.isfile(PARSER_SOURCE_PATH), f"{PARSER_SOURCE_PATH} does not exist"
    result = subprocess.run(
        ['gcc', '-shared', '-fPIC', '-o', SOURCE_CHECK_LIB, PARSER_SOURCE_PATH],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    assert result.returncode == 0, f"parser.c could not be compiled as a shared library:\n{result.stdout}"
    exercise_truncation(SOURCE_CHECK_LIB)


def test_run_supplied_test_script():
    if os.path.exists(RESULT_JSON_PATH):
        os.unlink(RESULT_JSON_PATH)
    result = subprocess.run(
        ['python3', os.path.join(WORKSPACE_DIR, 'test.py')],
        cwd=WORKSPACE_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=10
    )
    assert result.returncode == 0, f"test.py failed or crashed:\n{result.stdout}"


def test_result_json_exists_and_correct():
    assert os.path.isfile(RESULT_JSON_PATH), f"{RESULT_JSON_PATH} does not exist. Did you run test.py?"

    try:
        with open(RESULT_JSON_PATH, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{RESULT_JSON_PATH} does not contain valid JSON.")

    expected_key1 = "admin_status_ov"
    expected_val1 = "true"
    expected_key2 = "normal_k"
    expected_val2 = "normal_v"

    assert expected_key1 in data, f"Key '{expected_key1}' not found in result.json. Truncation logic might be incorrect."
    assert data[expected_key1] == expected_val1, f"Expected value for '{expected_key1}' to be '{expected_val1}', got '{data[expected_key1]}'."

    assert expected_key2 in data, f"Key '{expected_key2}' not found in result.json."
    assert data[expected_key2] == expected_val2, f"Expected value for '{expected_key2}' to be '{expected_val2}', got '{data[expected_key2]}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
