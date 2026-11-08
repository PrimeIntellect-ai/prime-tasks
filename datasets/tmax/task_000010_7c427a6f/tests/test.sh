#!/bin/bash
set -e
mkdir -p /logs/verifier

LOG_PATH=/home/user/app_trace.log
OUTPUT_PATH=/home/user/clean_traces.json
LOG_BACKUP=$(mktemp)
OUTPUT_BACKUP=$(mktemp)
cp "$LOG_PATH" "$LOG_BACKUP"
if [ -f "$OUTPUT_PATH" ]; then
    cp "$OUTPUT_PATH" "$OUTPUT_BACKUP"
    HAD_OUTPUT=1
else
    HAD_OUTPUT=0
fi

cleanup() {
    cp "$LOG_BACKUP" "$LOG_PATH"
    if [ "$HAD_OUTPUT" -eq 1 ]; then
        cp "$OUTPUT_BACKUP" "$OUTPUT_PATH"
    else
        rm -f "$OUTPUT_PATH"
    fi
    rm -f "$LOG_BACKUP" "$OUTPUT_BACKUP" /tmp/trace_execution.json
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import subprocess
import sys
import textwrap
import uuid

import pytest

SCRIPT_PATH = '/home/user/trace_analyzer.py'
LOG_PATH = '/home/user/app_trace.log'
OUTPUT_PATH = '/home/user/clean_traces.json'
TRACE_PATH = '/tmp/trace_execution.json'


def run_analyzer(command=None):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    command = command or [sys.executable, SCRIPT_PATH]
    result = subprocess.run(command, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, (
        f'trace_analyzer.py failed with exit code {result.returncode}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    assert os.path.isfile(OUTPUT_PATH), f'Output file not found: {OUTPUT_PATH}'
    try:
        with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'File {OUTPUT_PATH} is not valid JSON: {exc}')


def write_json_lines(records, corrupt_chunks=()):
    with open(LOG_PATH, 'wb') as f:
        for record in records:
            f.write(json.dumps(record).encode('utf-8') + b'\n')
        for chunk in corrupt_chunks:
            f.write(chunk + b'\n')


def catches_assertion_error(handler):
    node = handler.type
    if node is None:
        return False
    if isinstance(node, ast.Name):
        return node.id == 'AssertionError'
    if isinstance(node, ast.Attribute):
        return node.attr == 'AssertionError'
    if isinstance(node, ast.Tuple):
        return any(
            (isinstance(item, ast.Name) and item.id == 'AssertionError') or
            (isinstance(item, ast.Attribute) and item.attr == 'AssertionError')
            for item in node.elts
        )
    return False


def test_analyzer_is_executed_and_handles_required_cases():
    assert os.path.isfile(SCRIPT_PATH), f'Script not found: {SCRIPT_PATH}'

    # Execute against the supplied forensic log and retain the original exact check.
    supplied_data = run_analyzer()
    expected_supplied = {
        'T001': 'Init Process',
        'T002': 'Init Process -> Auth Module',
        'T005': 'Init Process -> Auth Module -> DB Query',
        'T006': 'Init Process -> Auth Module -> DB Query -> Render Response',
    }
    assert supplied_data == expected_supplied, (
        f'Content of {OUTPUT_PATH} does not match expected output. Got: {supplied_data}'
    )

    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        content = f.read()
    assert 'assert ' in content, "trace_analyzer.py does not contain an 'assert' statement as required."
    assert 'AssertionError' in content, "trace_analyzer.py does not catch 'AssertionError' as required."

    try:
        tree = ast.parse(content, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f'trace_analyzer.py is not valid Python: {exc}')

    assert_nodes = [node for node in ast.walk(tree) if isinstance(node, ast.Assert)]
    assertion_handlers = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.ExceptHandler) and catches_assertion_error(node)
    ]
    assert assert_nodes, 'No Python assert statement was found in trace_analyzer.py.'
    assert assertion_handlers, 'No except handler catches AssertionError.'

    # Use an invalid-only log and collect executed source lines. This proves that an
    # actual assert and its AssertionError handler are live on malformed trace IDs,
    # rather than merely appearing in comments or dead code.
    invalid_records = [
        {'trace_id': 'X123', 'parent_id': None, 'message': 'bad prefix'},
        {'trace_id': 'T12', 'parent_id': None, 'message': 'too short'},
        {'trace_id': 'T1234', 'parent_id': None, 'message': 'too long'},
        {'trace_id': 'T1A3', 'parent_id': None, 'message': 'not digits'},
    ]
    write_json_lines(invalid_records)
    monitor = textwrap.dedent(f'''\
        import json, os, runpy, sys
        target = os.path.abspath({SCRIPT_PATH!r})
        destination = {TRACE_PATH!r}
        executed = set()
        def tracer(frame, event, arg):
            if event == 'line' and os.path.abspath(frame.f_code.co_filename) == target:
                executed.add(frame.f_lineno)
            return tracer
        sys.settrace(tracer)
        try:
            runpy.run_path(target, run_name='__main__')
        finally:
            sys.settrace(None)
            with open(destination, 'w') as f:
                json.dump(sorted(executed), f)
    ''')
    invalid_data = run_analyzer([sys.executable, '-c', monitor])
    assert invalid_data == {}, f'Malformed trace IDs were not skipped: {invalid_data}'
    assert os.path.isfile(TRACE_PATH), 'Execution trace was not produced.'
    with open(TRACE_PATH, 'r', encoding='utf-8') as f:
        executed_lines = set(json.load(f))
    assert any(node.lineno in executed_lines for node in assert_nodes), (
        'No assert statement was executed while processing malformed trace IDs.'
    )
    handler_body_lines = {
        child.lineno
        for handler in assertion_handlers
        for statement in handler.body
        for child in ast.walk(statement)
        if hasattr(child, 'lineno')
    }
    assert handler_body_lines & executed_lines, (
        'The AssertionError handler was not executed for malformed trace IDs.'
    )

    # Exercise fresh, unpredictable messages and IDs, including corruption, a
    # cycle, a missing parent, and descendants of unresolvable traces.
    rng = random.SystemRandom()
    numbers = rng.sample(range(100, 999), 9)
    tids = [f'T{number:03d}' for number in numbers]
    root, child, leaf, cyc_a, cyc_b, missing, missing_child, cycle_child, extra = tids
    messages = [f'msg-{uuid.uuid4().hex}' for _ in range(9)]
    records = [
        {'trace_id': root, 'parent_id': None, 'message': messages[0]},
        {'trace_id': child, 'parent_id': root, 'message': messages[1]},
        {'trace_id': leaf, 'parent_id': child, 'message': messages[2]},
        {'trace_id': cyc_a, 'parent_id': cyc_b, 'message': messages[3]},
        {'trace_id': cyc_b, 'parent_id': cyc_a, 'message': messages[4]},
        {'trace_id': missing, 'parent_id': 'T000', 'message': messages[5]},
        {'trace_id': missing_child, 'parent_id': missing, 'message': messages[6]},
        {'trace_id': cycle_child, 'parent_id': cyc_a, 'message': messages[7]},
        {'trace_id': extra, 'parent_id': root, 'message': messages[8]},
        {'trace_id': 'X999', 'parent_id': root, 'message': 'invalid-prefix'},
        {'trace_id': 'T99', 'parent_id': None, 'message': 'invalid-length'},
    ]
    rng.shuffle(records)
    write_json_lines(records, [
        b'not json at all',
        b'{"trace_id": "T777",',
        b'corrupt\x00binary\xffdata',
    ])

    expected_dynamic = {
        root: messages[0],
        child: f'{messages[0]} -> {messages[1]}',
        leaf: f'{messages[0]} -> {messages[1]} -> {messages[2]}',
        extra: f'{messages[0]} -> {messages[8]}',
    }
    dynamic_data = run_analyzer()
    assert dynamic_data == expected_dynamic, (
        'Analyzer failed fresh corruption/cycle/missing-parent/format tests. '
        f'Expected {expected_dynamic}, got {dynamic_data}'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
