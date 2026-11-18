#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import shutil
import subprocess
import uuid

PROJECT = pathlib.Path('/home/user/project')
INPUT = PROJECT / 'input.log'
BUILD = PROJECT / 'build'
BINARY = BUILD / 'parser'
PARSED = pathlib.Path('/home/user/parsed_logs.txt')

ORIGINAL_INPUT = (
    '[OK] System booted\n'
    '[ERR] Disk full\n'
    '[OK] Network connected\n'
    '[WARN] High memory\n'
    '[OK] All services running\n'
    '[OK] Database initialized\n'
)
ORIGINAL_EXPECTED = [
    'All services running',
    'Database initialized',
    'Network connected',
    'System booted',
]


def run_parser(expected):
    env = os.environ.copy()
    env['LD_LIBRARY_PATH'] = '/home/user/deps/lib' + (
        ':' + env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else ''
    )
    result = subprocess.run(
        [str(BINARY)],
        cwd=str(BUILD),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f'parser exited with {result.returncode}. stderr: {result.stderr}'
    )
    assert result.stdout.splitlines() == expected, (
        f'parser output was incorrect. Expected {expected}, got '
        f'{result.stdout.splitlines()}. stderr: {result.stderr}'
    )


def test_parsed_logs_and_parser():
    parsed_logs_path = str(PARSED)
    input_log_path = str(INPUT)
    binary_path = str(BINARY)

    # Preserve the original final-state assertions.
    assert os.path.exists(binary_path), f'The compiled parser binary is missing at {binary_path}.'
    assert os.path.exists(parsed_logs_path), f'Expected output file {parsed_logs_path} does not exist.'
    assert os.path.exists(input_log_path), f'Input log file {input_log_path} does not exist.'

    expected_lines = []
    with open(input_log_path, 'r') as f:
        for line in f:
            if line.startswith('[OK] '):
                expected_lines.append(line[5:].strip())
    expected_lines.sort()

    with open(parsed_logs_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f'Contents of {parsed_logs_path} do not match the expected sorted parsed logs.\n'
        f'Expected: {expected_lines}\nActual: {actual_lines}'
    )

    # The supplied input is part of the task and must not be weakened or replaced.
    assert INPUT.read_text() == ORIGINAL_INPUT, 'input.log was modified.'
    assert actual_lines == ORIGINAL_EXPECTED

    # Reconfigure and rebuild from the submitted CMake/source files so a fabricated
    # file at the expected binary path cannot pass.
    shutil.rmtree(BUILD)
    BUILD.mkdir()
    subprocess.run(
        ['cmake', '-S', str(PROJECT), '-B', str(BUILD)],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=30,
    )
    subprocess.run(
        ['cmake', '--build', str(BUILD), '--clean-first'],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=60,
    )

    assert BINARY.is_file(), 'CMake did not produce build/parser.'
    assert os.access(BINARY, os.X_OK), 'build/parser is not executable.'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'build/parser is not an ELF executable.'

    env = os.environ.copy()
    env['LD_LIBRARY_PATH'] = '/home/user/deps/lib' + (
        ':' + env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else ''
    )
    linked = subprocess.run(
        ['ldd', str(BINARY)], env=env, check=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=10,
    ).stdout
    assert 'libsyslogger.so' in linked, 'parser was not linked to libsyslogger.so.'
    assert 'libsyslogger.so => not found' not in linked, 'libsyslogger.so is unresolved.'

    # Execute the rebuilt parser on the original input; the unfixed ownership bug
    # crashes as soon as an [OK] entry is processed.
    run_parser(ORIGINAL_EXPECTED)

    # Exercise the parser on verifier-generated data to reject hard-coded output.
    token = uuid.uuid4().hex
    messages = [
        f'Zulu-{token}',
        f'Alpha-{token}',
        f'Middle-{token}',
        f'Beta-{token}',
    ]
    generated = (
        f'[WARN] ignored-{token}\n'
        f'[OK] {messages[0]}\n'
        f'[ERR] ignored-too-{token}\n'
        f'[OK] {messages[1]}\n'
        f'[OK] {messages[2]}\n'
        f'[OK] {messages[3]}\n'
    )
    try:
        INPUT.write_text(generated)
        run_parser(sorted(messages))
    finally:
        INPUT.write_text(ORIGINAL_INPUT)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
