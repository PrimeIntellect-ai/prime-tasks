#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
import tempfile
from pathlib import Path

SOURCE = Path('/home/user/process_configs.c')
INPUT = Path('/home/user/config_logs.csv')
CLEAN = Path('/home/user/clean_logs.csv')
SUMMARY = Path('/home/user/summary.log')
HEADER = 'timestamp,service_name,user_email,changes_count'

ORIGINAL_ROWS = [
    '1700000000,nginx,admin@acme.corp,5',
    '1700000060,sshd,root@acme.corp,',
    '1700000120,nginx,dev@acme.corp,10',
    '1700000180,postgres,dba@acme.corp,',
    '1700000240,redis,cache@acme.corp,3',
]

ORIGINAL_EXPECTED = [
    'timestamp,service_name,user_email,changes_count',
    '1700000000,nginx,***@acme.corp,5',
    '1700000060,sshd,***@acme.corp,5',
    '1700000120,nginx,***@acme.corp,10',
    '1700000180,postgres,***@acme.corp,10',
    '1700000240,redis,***@acme.corp,3',
]


def write_input(rows):
    INPUT.write_text(HEADER + '\n' + '\n'.join(rows) + '\n')


def run_pipeline(binary, row_count):
    for output in (CLEAN, SUMMARY):
        try:
            output.unlink()
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [binary], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f'Compiled program exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )

    logged = [line.strip() for line in result.stdout.splitlines()
              if line.strip().startswith('Processing row ')]
    expected_logging = [f'Processing row {i}...' for i in range(1, row_count + 1)]
    assert logged == expected_logging, (
        f'Incorrect per-row stdout logging. Expected {expected_logging}, got {logged}'
    )
    assert CLEAN.exists(), f'Output file {CLEAN} is missing.'
    assert SUMMARY.exists(), f'Output file {SUMMARY} is missing.'


def assert_original_outputs():
    file_path = '/home/user/clean_logs.csv'
    assert os.path.exists(file_path), f'Output file {file_path} is missing.'

    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = ORIGINAL_EXPECTED
    assert len(lines) == len(expected_lines), (
        f'Expected {len(expected_lines)} lines in {file_path}, but got {len(lines)}.'
    )
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, (
            f'Line {i+1} in {file_path} is incorrect.\nExpected: {expected}\nGot: {actual}'
        )

    file_path = '/home/user/summary.log'
    assert os.path.exists(file_path), f'Output file {file_path} is missing.'
    with open(file_path, 'r') as f:
        content = f.read().strip()

    expected_content = 'Total Changes: 33'
    assert content == expected_content, (
        f"Content of {file_path} is incorrect.\nExpected: '{expected_content}'\nGot: '{content}'"
    )


def test_compiled_program_processes_original_and_unseen_inputs():
    assert SOURCE.exists(), f'Required C source file {SOURCE} is missing.'
    assert stat.S_ISREG(SOURCE.lstat().st_mode), f'{SOURCE} must be a regular file.'
    assert SOURCE.stat().st_size > 0, f'{SOURCE} is empty.'

    fd, binary = tempfile.mkstemp(prefix='verified_process_configs_', dir='/tmp')
    os.close(fd)
    os.unlink(binary)
    compile_result = subprocess.run(
        ['gcc', '-std=c11', '-O2', str(SOURCE), '-o', binary],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert compile_result.returncode == 0, (
        f'Failed to compile {SOURCE}.\nstdout:\n{compile_result.stdout}'
        f'\nstderr:\n{compile_result.stderr}'
    )

    try:
        write_input(ORIGINAL_ROWS)
        run_pipeline(binary, len(ORIGINAL_ROWS))
        assert_original_outputs()

        token = secrets.token_hex(5)
        a = 101 + secrets.randbelow(700)
        b = 101 + secrets.randbelow(700)
        c = 101 + secrets.randbelow(700)
        base = 1800000000 + secrets.randbelow(1000000)
        domain = f'{token}.internal'
        dynamic_rows = [
            f'{base},gateway,first_{token}@{domain},',
            f'{base+7},worker,second_{token}@{domain},{a}',
            f'{base+14},database,third_{token}@{domain},',
            f'{base+21},queue,fourth_{token}@{domain},{b}',
            f'{base+28},cache,fifth_{token}@{domain},',
            f'{base+35},scheduler,sixth_{token}@{domain},{c}',
        ]
        expected_counts = [0, a, a, b, b, c]
        services = ['gateway', 'worker', 'database', 'queue', 'cache', 'scheduler']
        expected_clean = [HEADER] + [
            f'{base + i*7},{services[i]},***@{domain},{expected_counts[i]}'
            for i in range(len(dynamic_rows))
        ]

        write_input(dynamic_rows)
        run_pipeline(binary, len(dynamic_rows))
        actual_clean = CLEAN.read_text().splitlines()
        assert actual_clean == expected_clean, (
            f'Cleaned output for unseen input is incorrect.\n'
            f'Expected: {expected_clean}\nGot: {actual_clean}'
        )
        expected_summary = f'Total Changes: {sum(expected_counts)}'
        actual_summary = SUMMARY.read_text().strip()
        assert actual_summary == expected_summary, (
            f'Incorrect summary for unseen input. Expected {expected_summary!r}, '
            f'got {actual_summary!r}'
        )
    finally:
        write_input(ORIGINAL_ROWS)
        try:
            run_pipeline(binary, len(ORIGINAL_ROWS))
        except Exception:
            pass
        try:
            os.unlink(binary)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
