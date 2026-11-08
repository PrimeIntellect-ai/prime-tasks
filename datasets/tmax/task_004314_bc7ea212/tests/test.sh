#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import calendar
import datetime
import os
from pathlib import Path
import re
import secrets
import subprocess

import pytest

SOURCE = Path('/home/user/audit_processor.c')
EXECUTABLE = Path('/home/user/audit_processor')
RAW = Path('/home/user/raw_audit_logs.txt')
OUTPUT = Path('/home/user/processed_audit.csv')

ORIGINAL_RAW = RAW.read_text() if RAW.is_file() else None
INITIAL_OUTPUT = OUTPUT.read_text() if OUTPUT.is_file() else None

EXPECTED_LINES = [
    '1696161600,admin,UPDATE,100,NONE',
    '1696161610,dev,READ,100,NONE',
    '1696161615,admin,DELETE,105,NONE',
    '1696161620,admin,UPDATE,110,NONE',
    '1696161625,admin,UPDATE,115,ANOMALY_RATE',
    '1696161630,admin,UPDATE,180,ANOMALY_RATE|ANOMALY_VERSION',
    '1696161635,dev,WRITE,180,NONE',
    '1696161710,admin,READ,185,NONE',
]

LOG_RE = re.compile(
    r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] '
    r'IP=(\S+) USER=(\S+) ACTION=(\S+) CONFIG_V=(\d+) RETRY=([01])$'
)


def nonempty_lines(text):
    return [line.strip() for line in text.splitlines() if line.strip()]


def oracle(raw_text):
    result = []
    previous_valid = None
    user_actions = {}
    maximum = None

    for raw_line in raw_text.splitlines():
        match = LOG_RE.fullmatch(raw_line)
        if not match:
            continue
        try:
            parsed_time = datetime.datetime.strptime(match.group(1), '%Y-%m-%d %H:%M:%S')
        except ValueError:
            continue

        timestamp = calendar.timegm(parsed_time.timetuple())
        user = match.group(3)
        action = match.group(4)
        version = int(match.group(5))

        duplicate = False
        if previous_valid is not None:
            prev_user, prev_action, prev_version, prev_time = previous_valid
            duplicate = (
                user == prev_user and action == prev_action and version == prev_version
                and 0 <= timestamp - prev_time <= 10
            )
        previous_valid = (user, action, version, timestamp)
        if duplicate:
            continue

        recent = [t for t in user_actions.get(user, []) if 0 <= timestamp - t <= 60]
        rate_anomaly = len(recent) >= 3
        recent.append(timestamp)
        user_actions[user] = recent

        version_anomaly = maximum is not None and version > maximum + 50
        if maximum is None or version > maximum:
            maximum = version

        flags = []
        if rate_anomaly:
            flags.append('ANOMALY_RATE')
        if version_anomaly:
            flags.append('ANOMALY_VERSION')
        if not flags:
            flags.append('NONE')
        result.append(f'{timestamp},{user},{action},{version},{"|".join(flags)}')

    return result


def run_processor(raw_text):
    RAW.write_text(raw_text)
    if OUTPUT.exists():
        OUTPUT.unlink()
    completed = subprocess.run(
        [str(EXECUTABLE)], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert completed.returncode == 0, (
        f'Processor exited with {completed.returncode}.\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )
    assert OUTPUT.exists(), 'Processor did not create /home/user/processed_audit.csv'
    assert OUTPUT.is_file(), '/home/user/processed_audit.csv is not a regular file'
    return nonempty_lines(OUTPUT.read_text())


def make_line(base, offset, ip, user, action, version, retry=0):
    stamp = datetime.datetime.fromtimestamp(base + offset, datetime.timezone.utc)
    return (
        f'[{stamp:%Y-%m-%d %H:%M:%S}] IP={ip} USER={user} '
        f'ACTION={action} CONFIG_V={version} RETRY={retry}'
    )


def test_source_code_exists():
    file_path = '/home/user/audit_processor.c'
    assert os.path.exists(file_path), f'The source code file {file_path} is missing.'
    assert os.path.isfile(file_path), f'The path {file_path} is not a file.'


def test_executable_exists():
    file_path = '/home/user/audit_processor'
    assert os.path.exists(file_path), f'The executable {file_path} is missing.'
    assert os.path.isfile(file_path), f'The path {file_path} is not a file.'
    assert os.access(file_path, os.X_OK), f'The file {file_path} is not executable.'


def test_output_csv_exists():
    file_path = '/home/user/processed_audit.csv'
    assert os.path.exists(file_path), f'The output file {file_path} is missing. Did the program run successfully?'
    assert os.path.isfile(file_path), f'The path {file_path} is not a file.'


def test_output_csv_content():
    if INITIAL_OUTPUT is None:
        pytest.fail('Cannot verify content because /home/user/processed_audit.csv is missing.')
    lines = nonempty_lines(INITIAL_OUTPUT)
    assert len(lines) == len(EXPECTED_LINES), (
        f'Expected {len(EXPECTED_LINES)} lines in output CSV, but found {len(lines)}.'
    )
    for i, (actual, expected) in enumerate(zip(lines, EXPECTED_LINES)):
        assert actual == expected, f'Line {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}'


def test_compile_and_behavior():
    source_text = SOURCE.read_text()
    assert re.search(r'#\s*include\s*<regex\.h>', source_text), 'Source must include POSIX regex.h'
    assert re.search(r'\bregcomp\s*\(', source_text), 'Source must compile a POSIX regular expression'
    assert re.search(r'\bregexec\s*\(', source_text), 'Source must execute a POSIX regular expression'

    compiled = subprocess.run(
        ['gcc', '-o', str(EXECUTABLE), str(SOURCE), '-Wall'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert compiled.returncode == 0, (
        f'gcc failed with {compiled.returncode}.\nstdout:\n{compiled.stdout}\nstderr:\n{compiled.stderr}'
    )
    assert EXECUTABLE.is_file() and os.access(EXECUTABLE, os.X_OK)

    assert ORIGINAL_RAW is not None, 'Original raw audit log is missing'
    original_actual = run_processor(ORIGINAL_RAW)
    assert original_actual == oracle(ORIGINAL_RAW)
    assert original_actual == EXPECTED_LINES

    nonce = secrets.token_hex(5)
    user_a = 'alpha_' + nonce
    user_b = 'beta_' + nonce
    user_c = 'gamma_' + nonce
    base = 1700000000 + secrets.randbelow(1000000)
    initial_version = 70 + secrets.randbelow(100)

    lines = [
        make_line(base, 0, '10.1.1.1', user_a, 'SET', initial_version, 0),
        'CORRUPTED LINE BETWEEN VALID RECORDS',
        make_line(base, 5, '10.1.1.1', user_a, 'SET', initial_version, 1),
        make_line(base, 8, '10.2.2.2', user_b, 'READ', 3, 0),
        make_line(base, 10, '10.1.1.1', user_a, 'EDIT', initial_version + 1, 0),
        make_line(base, 20, '10.1.1.1', user_a, 'WRITE', initial_version + 2, 0),
        make_line(base, 60, '10.1.1.1', user_a, 'APPLY', initial_version + 3, 0),
        make_line(base, 61, '10.3.3.3', user_c, 'JUMP', initial_version + 54, 0),
        make_line(base, 62, '10.1.1.1', user_a, 'COMMIT', initial_version + 110, 0),
        make_line(base, 63, '10.2.2.2', user_b, 'READ', 3, 1),
        make_line(base, 130, '10.1.1.1', user_a, 'LATE', initial_version + 111, 0),
        make_line(base, 131, '10.9.9.9', user_c, 'BAD', 999, 0) + ' TRAILING',
        '[2023-99-99 12:00:00] IP=1.2.3.4 USER=x ACTION=y CONFIG_V=1 RETRY=0',
        make_line(base, 132, '10.9.9.9', user_c, 'BADRETRY', 999, 0).replace('RETRY=0', 'RETRY=2'),
    ]
    generated_raw = '\n'.join(lines) + '\n'
    assert run_processor(generated_raw) == oracle(generated_raw)

    # Re-run with a second fresh input to ensure output is regenerated rather than cached.
    second_base = base + 1000
    second_lines = [
        make_line(second_base, 0, '192.0.2.1', user_b, 'ONE', 500, 0),
        make_line(second_base, 15, '192.0.2.1', user_b, 'TWO', 10, 0),
        make_line(second_base, 30, '192.0.2.1', user_b, 'THREE', 551, 0),
        make_line(second_base, 45, '192.0.2.1', user_b, 'FOUR', 552, 0),
        make_line(second_base, 106, '192.0.2.1', user_b, 'FIVE', 553, 0),
    ]
    second_raw = '\n'.join(second_lines) + '\n'
    assert run_processor(second_raw) == oracle(second_raw)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
