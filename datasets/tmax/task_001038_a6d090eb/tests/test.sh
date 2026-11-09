#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import pathlib
import re
import subprocess
import sys
import uuid

import pytest

HOME = pathlib.Path('/home/user')
WRAPPER = HOME / 'run_processor.sh'
PROCESSOR = HOME / 'process_logs.py'
MRE = HOME / 'mre.py'
INPUT = HOME / 'uptime.jsonl'
INVALID = HOME / 'invalid_logs.txt'

CANONICAL_INPUT = (
    '{"url": "site1.com", "uptime": 99}\n'
    '{"url": "site2.com", "uptime": 98\n'
    '{"url": "site3.com", "uptime": 100}\n'
)
CANONICAL_INVALID = '{"url": "site2.com", "uptime": 98\n'
VALID_MRE = '{"url": "site1.com", "uptime": 99}'
INVALID_MRE = '{"url": "site2.com", "uptime": 98'


def run(command, env=None):
    return subprocess.run(command, capture_output=True, text=True, env=env, timeout=15)


def assert_success(result, description):
    assert result.returncode == 0, (
        f'{description} failed with exit code {result.returncode}. '
        f'stdout: {result.stdout!r}; stderr: {result.stderr!r}'
    )


def json_loads_call(node):
    return (
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and isinstance(node.func.value, ast.Name)
        and node.func.value.id == 'json'
        and node.func.attr == 'loads'
    )


def json_decode_handler(handler):
    kind = handler.type
    return (
        isinstance(kind, ast.Name) and kind.id == 'JSONDecodeError'
    ) or (
        isinstance(kind, ast.Attribute) and kind.attr == 'JSONDecodeError'
    )


def has_required_json_try(tree):
    for node in ast.walk(tree):
        if not isinstance(node, ast.Try):
            continue
        parses_in_try = any(json_loads_call(child) for statement in node.body for child in ast.walk(statement))
        catches_decode_error = any(json_decode_handler(handler) for handler in node.handlers)
        if parses_in_try and catches_decode_error:
            return True
    return False


def test_run_processor_success_and_canonical_output():
    assert WRAPPER.is_file(), f'File {WRAPPER} is missing.'
    assert PROCESSOR.is_file(), f'File {PROCESSOR} is missing.'

    INPUT.write_text(CANONICAL_INPUT)
    INVALID.unlink(missing_ok=True)
    result = run(['bash', str(WRAPPER)])
    assert_success(result, 'run_processor.sh')

    assert 'Processed 2 valid logs with timeout 5' in result.stdout, (
        'The wrapper must supply the corrected integer timeout and the processor '
        f'must count both valid records. stdout was {result.stdout!r}'
    )


def test_invalid_logs_content():
    assert INVALID.is_file(), f'File {INVALID} is missing. Did process_logs.py create it?'
    content = INVALID.read_text()
    assert content == CANONICAL_INVALID, (
        f'invalid_logs.txt content is incorrect. Expected: {CANONICAL_INVALID!r}, Got: {content!r}'
    )


def test_processor_handles_derived_records_and_appends_raw_lines():
    token = uuid.uuid4().hex
    timeout = 20 + int(token[:2], 16)
    valid_records = [
        {'url': token + '.example', 'uptime': 0},
        {'url': 'quoted-' + token, 'uptime': 100, 'meta': {'ok': True}},
        [token, 17, None],
    ]
    invalid_lines = [
        '{"url": "' + token + '", "uptime": ',
        'not-json-' + token,
    ]
    lines = [
        json.dumps(valid_records[0]) + '\n',
        invalid_lines[0] + '\n',
        json.dumps(valid_records[1]) + '\n',
        invalid_lines[1] + '\n',
        json.dumps(valid_records[2]) + '\n',
    ]
    seed = 'preexisting-' + token + '\n'

    INPUT.write_text(''.join(lines))
    INVALID.write_text(seed)
    env = os.environ.copy()
    env['TIMEOUT_SECS'] = str(timeout)

    try:
        result = run(['python3', str(PROCESSOR)], env=env)
        assert_success(result, 'process_logs.py')
        expected_summary = f'Processed {len(valid_records)} valid logs with timeout {timeout}'
        assert expected_summary in result.stdout, (
            'process_logs.py did not honor the integer environment value or correctly '
            f'count dynamically generated valid JSON. stdout was {result.stdout!r}'
        )
        expected_invalid = seed + ''.join(line + '\n' for line in invalid_lines)
        assert INVALID.read_text() == expected_invalid, (
            'Every dynamically generated malformed line must be appended verbatim, '
            'including its trailing newline, without replacing existing content.'
        )
    finally:
        INPUT.write_text(CANONICAL_INPUT)
        INVALID.unlink(missing_ok=True)
        cleanup = run(['bash', str(WRAPPER)])
        assert_success(cleanup, 'run_processor.sh during state restoration')


def test_both_scripts_use_json_loads_with_jsondecodeerror_handling():
    processor_tree = ast.parse(PROCESSOR.read_text(), filename=str(PROCESSOR))
    mre_tree = ast.parse(MRE.read_text(), filename=str(MRE))
    assert has_required_json_try(processor_tree), (
        'process_logs.py must call json.loads inside a try block that catches json.JSONDecodeError.'
    )
    assert has_required_json_try(mre_tree), (
        'mre.py must demonstrate the same json.loads and JSONDecodeError try/except parsing pattern.'
    )


def test_mre_script_exists_contains_both_strings_and_runs():
    assert MRE.is_file(), f'File {MRE} is missing.'
    content = MRE.read_text()
    assert INVALID_MRE in content, f'mre.py must hardcode the incomplete JSON string: {INVALID_MRE}'
    assert VALID_MRE in content, f'mre.py must hardcode the valid JSON string: {VALID_MRE}'

    result = run(['python3', str(MRE)])
    assert_success(result, 'mre.py')


def test_mre_processes_both_literals_and_performs_no_file_reads():
    source = MRE.read_text()
    tree = ast.parse(source, filename=str(MRE))

    forbidden_names = {'open'}
    forbidden_attributes = {
        'open', 'read', 'readline', 'readlines', 'read_text', 'read_bytes'
    }
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name):
            assert node.func.id not in forbidden_names, 'mre.py must not read from files.'
        if isinstance(node.func, ast.Attribute):
            assert node.func.attr not in forbidden_attributes, 'mre.py must not read from files.'

    code = compile(source, str(MRE), 'exec')
    seen = []
    forbidden_open_events = []
    real_loads = json.loads

    def tracked_loads(value, *args, **kwargs):
        seen.append(value)
        return real_loads(value, *args, **kwargs)

    audit_active = {'value': False}

    def audit_hook(event, args):
        if audit_active['value'] and event == 'open':
            forbidden_open_events.append(args)
            raise RuntimeError('mre.py attempted to open a file')

    sys.addaudithook(audit_hook)
    json.loads = tracked_loads
    audit_active['value'] = True
    try:
        namespace = {'__name__': '__main__', '__file__': str(MRE)}
        exec(code, namespace, namespace)
    finally:
        audit_active['value'] = False
        json.loads = real_loads

    assert forbidden_open_events == [], 'mre.py attempted to read or open a file.'
    assert VALID_MRE in seen, 'mre.py did not pass the required valid hardcoded string to json.loads.'
    assert INVALID_MRE in seen, 'mre.py did not pass the required incomplete hardcoded string to json.loads.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
