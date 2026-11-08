#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import pytest

FIXED = '/home/user/server_fixed'
SERVER_C = '/home/user/server.c'
PROCESSOR_C = '/home/user/processor.c'
BUILT = '/tmp/verifier_server_from_sources'


def run_server(path, input_data, timeout=2.0):
    try:
        return subprocess.run(
            [path],
            input=input_data,
            text=True,
            capture_output=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f'{path} timed out while processing test input.')


def expected_output(lines):
    output = ['System initialized.', 'Service ready.']
    for line in lines:
        if line == 'QUIT':
            break
        if line.startswith('CMD:'):
            output.append(f'Processed command: {line}')
        else:
            output.append(f'Ignored: {line}')
    return '\n'.join(output) + '\n'


def assert_valgrind_clean(path, input_data):
    try:
        result = subprocess.run(
            ['valgrind', '--leak-check=full', '--error-exitcode=1', path],
            input=input_data,
            text=True,
            capture_output=True,
            timeout=5.0,
        )
    except FileNotFoundError:
        pytest.fail('valgrind is not installed or not in PATH.')
    except subprocess.TimeoutExpired:
        pytest.fail(f'The valgrind process timed out for {path}.')

    assert result.returncode == 0, (
        f'Valgrind or the service reported an error for {path}:\n{result.stderr}'
    )
    stderr_lower = result.stderr.lower()
    if 'definitely lost:' in stderr_lower or 'indirectly lost:' in stderr_lower:
        if 'definitely lost: 0 bytes' not in stderr_lower:
            pytest.fail(f'Memory leak detected by valgrind:\n{result.stderr}')
    assert re.search(r'definitely lost:\s*0 bytes', stderr_lower), result.stderr
    assert re.search(r'indirectly lost:\s*0 bytes', stderr_lower), result.stderr


def test_server_fixed_exists_and_executable():
    assert os.path.isfile(FIXED), f'The compiled executable {FIXED} is missing.'
    assert os.access(FIXED, os.X_OK), f'The file {FIXED} is not executable.'
    with open(FIXED, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'server_fixed must be a compiled ELF executable.'


def test_poison_pill_content():
    path = '/home/user/poison_pill.txt'
    assert os.path.isfile(path), f'The file {path} is missing.'
    with open(path, 'r') as f:
        content = f.read().strip()

    assert content.startswith('CMD:'), "The poison pill string must start with 'CMD:' to trigger the vulnerable code path."
    assert ';' not in content, "The poison pill string must not contain a ';' character, as that would prevent the infinite loop in the original code."


def test_recovered_sources_compile():
    assert os.path.isfile(SERVER_C), f'{SERVER_C} is missing.'
    assert os.path.isfile(PROCESSOR_C), f'{PROCESSOR_C} is missing.'
    result = subprocess.run(
        ['gcc', SERVER_C, PROCESSOR_C, '-o', BUILT],
        text=True,
        capture_output=True,
    )
    assert result.returncode == 0, (
        'server.c and processor.c did not compile and link with the required command:\n'
        + result.stdout + result.stderr
    )
    assert os.path.isfile(BUILT) and os.access(BUILT, os.X_OK)


def test_compiled_sources_and_final_binary_preserve_service_behavior():
    token_a = secrets.token_hex(12)
    token_b = secrets.token_hex(12)
    lines = [
        f'plain-{token_a}',
        f'CMD:{token_a};',
        f'CMD:{token_b}',
        f'CMD:{token_b};trailing-data',
        '',
        'QUIT',
    ]
    input_data = '\n'.join(lines) + '\n'
    expected = expected_output(lines)

    for path in (BUILT, FIXED):
        result = run_server(path, input_data)
        assert result.returncode == 0, f'{path} exited with {result.returncode}: {result.stderr}'
        assert result.stdout == expected, (
            f'{path} changed the intended process_input output.\n'
            f'Expected:\n{expected!r}\nActual:\n{result.stdout!r}'
        )


def test_server_fixed_no_infinite_loop():
    pill_path = '/home/user/poison_pill.txt'
    with open(pill_path, 'r') as f:
        pill_content = f.read().strip()

    input_data = f'{pill_content}\nQUIT\n'
    result = run_server(FIXED, input_data, timeout=2.0)
    assert result.returncode == 0, 'The server did not exit with a 0 return code.'

    source_result = run_server(BUILT, input_data, timeout=2.0)
    assert source_result.returncode == 0, 'The executable compiled from the submitted sources did not exit successfully.'


def test_server_fixed_no_memory_leak():
    pill_path = '/home/user/poison_pill.txt'
    with open(pill_path, 'r') as f:
        pill_content = f.read().strip()
    input_data = f'CMD:VALID;\n{pill_content}\nQUIT\n'
    assert_valgrind_clean(FIXED, input_data)


def test_compiled_sources_no_memory_leak():
    token = secrets.token_hex(10)
    input_data = f'ordinary-{token}\nCMD:{token};\nCMD:{token}\nQUIT\n'
    assert_valgrind_clean(BUILT, input_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
