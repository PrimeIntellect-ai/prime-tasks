#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from pathlib import Path
import shutil
import subprocess
import pytest

PROJECT = Path('/home/user/project')
TEST_SCRIPT = PROJECT / 'test_builder.py'
RESULTS = PROJECT / 'test_results.json'
BUILDER = PROJECT / 'builder.py'
SOURCE = PROJECT / 'fast_math.c'
CALL_LOG = Path('/tmp/verifier_builder_calls.jsonl')

CANONICAL_BUILDER = '''import subprocess
import os
import json


def build_target(arch, source_file):
    with open('/tmp/verifier_builder_calls.jsonl', 'a') as log:
        log.write(json.dumps({'arch': arch, 'source_file': source_file}) + '\\n')

    compiler = 'gcc'
    if arch == 'aarch64':
        compiler = 'aarch64-linux-gnu-gcc'

    output_file = source_file.replace('.c', '.s')

    # We only generate assembly code (-S) to allow assembly-level analysis
    cmd = [compiler, '-S', '-O2', source_file, '-o', output_file]
    if arch == 'x86_64':
        cmd.insert(1, '-m64')

    subprocess.run(cmd, check=True)
    return output_file
'''

CANONICAL_SOURCE = '''int multiply(int a, int b) {
    return a * b;
}
'''

NO_MULTIPLY_SOURCE = '''int multiply(int a, int b) {
    return a + b;
}
'''


def clear_runtime_files():
    RESULTS.unlink(missing_ok=True)
    CALL_LOG.unlink(missing_ok=True)
    (PROJECT / 'fast_math.s').unlink(missing_ok=True)
    shutil.rmtree(PROJECT / '__pycache__', ignore_errors=True)


def execute_suite():
    clear_runtime_files()
    env = os.environ.copy()
    env['PYTHONDONTWRITEBYTECODE'] = '1'
    completed = subprocess.run(
        ['python3', str(TEST_SCRIPT)],
        cwd=str(PROJECT),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert RESULTS.is_file(), (
        'Executing test_builder.py did not create test_results.json.\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )
    try:
        data = json.loads(RESULTS.read_text())
    except json.JSONDecodeError as exc:
        pytest.fail(f'Executing test_builder.py produced invalid JSON: {exc}')
    assert isinstance(data, dict)
    assert set(data) == {'tests_run', 'failures', 'errors'}, (
        'test_results.json must have the exact required structure'
    )
    for key in ('tests_run', 'failures', 'errors'):
        assert isinstance(data[key], int) and not isinstance(data[key], bool)
    return data, completed


def recorded_calls():
    assert CALL_LOG.is_file(), 'The tests never called builder.build_target'
    return [json.loads(line) for line in CALL_LOG.read_text().splitlines() if line]


def test_execute_and_exercise_test_builder():
    assert TEST_SCRIPT.is_file(), f'The file {TEST_SCRIPT} does not exist.'
    assert BUILDER.is_file()
    assert SOURCE.is_file()

    old_builder = BUILDER.read_bytes()
    old_source = SOURCE.read_bytes()
    try:
        # First run against the real build behavior and verify both required calls occur.
        BUILDER.write_text(CANONICAL_BUILDER)
        SOURCE.write_text(CANONICAL_SOURCE)
        results, _ = execute_suite()
        assert results['tests_run'] >= 2
        assert results['failures'] == 0
        assert results['errors'] == 0
        calls = recorded_calls()
        assert {'arch': 'aarch64', 'source_file': 'fast_math.c'} in calls, (
            "The suite did not call build_target('aarch64', 'fast_math.c')"
        )
        assert {'arch': 'x86_64', 'source_file': 'fast_math.c'} in calls, (
            "The suite did not call build_target('x86_64', 'fast_math.c')"
        )

        # A correct mock assertion must detect that the aarch64 branch chose gcc.
        wrong_builder = CANONICAL_BUILDER.replace(
            "compiler = 'aarch64-linux-gnu-gcc'",
            "compiler = 'gcc'",
        )
        BUILDER.write_text(wrong_builder)
        SOURCE.write_text(CANONICAL_SOURCE)
        results, _ = execute_suite()
        assert results['tests_run'] >= 2
        assert results['failures'] + results['errors'] > 0, (
            'The suite did not reject an incorrect aarch64 compiler selection'
        )

        # A correct integration assertion must detect assembly with no imul.
        BUILDER.write_text(CANONICAL_BUILDER)
        SOURCE.write_text(NO_MULTIPLY_SOURCE)
        results, _ = execute_suite()
        assert results['tests_run'] >= 2
        assert results['failures'] + results['errors'] > 0, (
            "The suite did not reject x86_64 assembly that lacks 'imul'"
        )

        # Leave a fresh successful log produced by an actual final execution.
        BUILDER.write_text(CANONICAL_BUILDER)
        SOURCE.write_text(CANONICAL_SOURCE)
        results, _ = execute_suite()
        assert results['tests_run'] >= 2
        assert results['failures'] == 0
        assert results['errors'] == 0
    finally:
        BUILDER.write_bytes(old_builder)
        SOURCE.write_bytes(old_source)
        shutil.rmtree(PROJECT / '__pycache__', ignore_errors=True)


def test_test_results_json():
    json_path = '/home/user/project/test_results.json'
    assert os.path.isfile(json_path), f"The file {json_path} does not exist. Did you run your test script?"

    with open(json_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} is not valid JSON.")

    assert "tests_run" in results, "Key 'tests_run' missing in test_results.json"
    assert "failures" in results, "Key 'failures' missing in test_results.json"
    assert "errors" in results, "Key 'errors' missing in test_results.json"

    assert results["tests_run"] >= 2, f"Expected at least 2 tests run, got {results['tests_run']}"
    assert results["failures"] == 0, f"Expected 0 failures, got {results['failures']}"
    assert results["errors"] == 0, f"Expected 0 errors, got {results['errors']}"


def test_test_builder_py_content():
    py_path = '/home/user/project/test_builder.py'
    assert os.path.isfile(py_path), f"The file {py_path} does not exist."

    with open(py_path, 'r') as f:
        content = f.read()

    assert "mock" in content, "test_builder.py does not seem to use 'mock' as required."
    assert "imul" in content, "test_builder.py does not seem to check for the 'imul' instruction."
    assert "unittest" in content, "test_builder.py does not seem to use 'unittest'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
