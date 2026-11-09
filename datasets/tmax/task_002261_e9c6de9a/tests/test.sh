#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.metadata
import os
import py_compile
import secrets
import struct
import subprocess
import sys
import tempfile

import pytest

SETUP_PATH = '/home/user/app/setup.py'
PARSER_PATH = '/home/user/app/parser.py'
FAILURES_PATH = '/home/user/failures.txt'


def test_setup_py_compiles():
    """Verify that setup.py no longer has a syntax error."""
    assert os.path.exists(SETUP_PATH), f"{SETUP_PATH} is missing."
    try:
        py_compile.compile(SETUP_PATH, doraise=True)
    except py_compile.PyCompileError as e:
        pytest.fail(f"setup.py still has a syntax error: {e}")


def test_package_installed():
    """Verify that the logparser package is installed."""
    try:
        importlib.metadata.version('logparser')
    except importlib.metadata.PackageNotFoundError:
        pytest.fail("Package 'logparser' is not installed. Did you run pip install -e /home/user/app?")


def test_failures_log_exists_and_correct():
    """Retain the original check that the provided corrupted log was processed."""
    assert os.path.exists(FAILURES_PATH), (
        f"{FAILURES_PATH} does not exist. Did the script run and catch the error?"
    )
    with open(FAILURES_PATH, 'r') as f:
        content = f.read().strip()

    expected_string = 'MALFORMED_RECORD_AT_OFFSET_8'
    assert expected_string in content, (
        f"Expected to find '{expected_string}' in {FAILURES_PATH}, but got:\n{content}"
    )


def _is_struct_error(node):
    return (
        isinstance(node, ast.Attribute)
        and isinstance(node.value, ast.Name)
        and node.value.id == 'struct'
        and node.attr == 'error'
    )


def _catches_struct_error(node):
    if _is_struct_error(node):
        return True
    if isinstance(node, ast.Tuple):
        return any(_is_struct_error(item) for item in node.elts)
    return False


def _is_struct_unpack(call):
    return (
        isinstance(call, ast.Call)
        and isinstance(call.func, ast.Attribute)
        and isinstance(call.func.value, ast.Name)
        and call.func.value.id == 'struct'
        and call.func.attr == 'unpack'
    )


def test_payload_unpack_has_required_handler_and_break():
    """Inspect that payload unpacking is protected by struct.error and exits the loop."""
    assert os.path.isfile(PARSER_PATH), f'{PARSER_PATH} is missing or is not a file.'
    with open(PARSER_PATH, 'r', encoding='utf-8') as f:
        tree = ast.parse(f.read(), filename=PARSER_PATH)

    matching_handlers = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Try):
            continue
        try_calls = [
            child
            for statement in node.body
            for child in ast.walk(statement)
            if _is_struct_unpack(child)
        ]
        if not try_calls:
            continue
        for handler in node.handlers:
            if handler.type is not None and _catches_struct_error(handler.type):
                matching_handlers.append(handler)

    assert matching_handlers, (
        'The payload struct.unpack call must be inside a try block with an '
        'except struct.error handler.'
    )
    assert any(
        handler.body and isinstance(handler.body[-1], ast.Break)
        for handler in matching_handlers
    ), 'The struct.error handler must end by immediately breaking out of the parsing loop.'


def test_parser_handles_derived_truncated_records_and_appends():
    """Execute the submitted parser against unpredictable malformed records."""
    old_exists = os.path.exists(FAILURES_PATH)
    old_content = None
    if old_exists:
        with open(FAILURES_PATH, 'rb') as f:
            old_content = f.read()

    try:
        for case in range(4):
            blob = bytearray()
            record_count = case + 1
            for _ in range(record_count):
                payload = secrets.token_bytes(secrets.randbelow(12) + 1)
                blob.extend(struct.pack('<I', len(payload)))
                blob.extend(payload)

            malformed_offset = len(blob)
            short_payload = secrets.token_bytes(secrets.randbelow(7))
            declared_length = len(short_payload) + secrets.randbelow(20) + 1
            blob.extend(struct.pack('<I', declared_length))
            blob.extend(short_payload)

            marker = f'PREEXISTING_{secrets.token_hex(8)}\n'
            with open(FAILURES_PATH, 'w', encoding='utf-8') as f:
                f.write(marker)

            fd, input_path = tempfile.mkstemp(prefix='parser-case-', suffix='.bin')
            try:
                with os.fdopen(fd, 'wb') as f:
                    f.write(blob)
                result = subprocess.run(
                    [sys.executable, PARSER_PATH, input_path],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=5,
                    check=False,
                )
            finally:
                os.unlink(input_path)

            assert result.returncode == 0, (
                f'Parser crashed on a truncated record (exit {result.returncode}).\n'
                f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
            )
            with open(FAILURES_PATH, 'r', encoding='utf-8') as f:
                actual = f.read()
            expected = marker + f'MALFORMED_RECORD_AT_OFFSET_{malformed_offset}\n'
            assert actual == expected, (
                'Parser must preserve existing log contents and append exactly one '
                f'correctly derived failure line. Expected {expected!r}, got {actual!r}.'
            )
    finally:
        if old_exists:
            with open(FAILURES_PATH, 'wb') as f:
                f.write(old_content)
        elif os.path.exists(FAILURES_PATH):
            os.unlink(FAILURES_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
