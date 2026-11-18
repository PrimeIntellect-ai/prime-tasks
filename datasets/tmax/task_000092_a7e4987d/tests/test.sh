#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import shlex
import subprocess
from collections import deque

import pytest

PROJECT = '/home/user/drift_monitor'
BINARY = PROJECT + '/target/release/drift_monitor'
INPUT = '/app/config_logs.csv'
REPORT = '/home/user/drift_report.txt'
LINE_RE = re.compile(
    r'^\[(\d+)\] Server config drift detected\. Rolling average config size: (\d+\.\d{2}) bytes\.$'
)


def read_spec():
    result = subprocess.run(
        ['tesseract', '/app/config_spec.png', 'stdout'],
        capture_output=True,
        text=True,
        check=True,
        timeout=20,
    )
    window = re.search(r'WINDOW_SIZE\s*=\s*(\d+)', result.stdout)
    threshold = re.search(r'DRIFT_THRESHOLD\s*=\s*(\d+)', result.stdout)
    assert window and threshold, f'Could not extract configuration from image: {result.stdout!r}'
    return int(window.group(1)), int(threshold.group(1))


def reference(rows):
    window_size, threshold = read_spec()
    active = deque()
    total = 0
    expected = []
    for timestamp, server_id, config_bytes in sorted(rows, key=lambda row: row[0]):
        active.append((timestamp, config_bytes))
        total += config_bytes
        cutoff = timestamp - window_size
        while active and active[0][0] < cutoff:
            _, old_value = active.popleft()
            total -= old_value
        if len(active) > threshold:
            expected.append((timestamp, total / len(active)))
    return expected


def write_input(rows):
    with open(INPUT, 'w', newline='') as handle:
        writer = csv.writer(handle, lineterminator='\n')
        writer.writerow(['timestamp', 'server_id', 'config_bytes'])
        writer.writerows(rows)
    os.chmod(INPUT, 0o666)


def run_binary(rows):
    with open(INPUT, 'rb') as handle:
        original_input = handle.read()
    try:
        write_input(rows)
        if os.path.lexists(REPORT):
            os.unlink(REPORT)
        result = subprocess.run(
            ['runuser', '-u', 'user', '--', BINARY],
            cwd=PROJECT,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f'drift_monitor exited with {result.returncode}. '
            f'stdout={result.stdout!r}, stderr={result.stderr!r}'
        )
        assert os.path.isfile(REPORT), f'Report file {REPORT} does not exist after running the binary.'
        with open(REPORT, 'r') as handle:
            return handle.read()
    finally:
        with open(INPUT, 'wb') as handle:
            handle.write(original_input)
        os.chmod(INPUT, 0o666)


def parse_exact_report(content):
    lines = content.splitlines()
    parsed = []
    for line in lines:
        match = LINE_RE.fullmatch(line)
        assert match, f'Report line does not have the required exact format: {line!r}'
        parsed.append((int(match.group(1)), float(match.group(2))))
    return parsed


def assert_matches_reference(content, rows):
    actual = parse_exact_report(content)
    expected = reference(rows)
    assert len(actual) == len(expected), f'Expected {len(expected)} report entries, found {len(actual)}.'
    for (actual_ts, actual_avg), (expected_ts, expected_avg) in zip(actual, expected):
        assert actual_ts == expected_ts, f'Expected timestamp {expected_ts}, found {actual_ts}.'
        assert abs(actual_avg - expected_avg) <= 0.0051, (
            f'Incorrect average at {expected_ts}: expected {expected_avg:.8f}, found {actual_avg:.2f}'
        )


def test_rust_project_and_binary_exist():
    assert os.path.isfile(PROJECT + '/Cargo.toml'), 'Cargo.toml is missing from the Rust project.'
    assert os.path.isfile(PROJECT + '/src/main.rs'), 'src/main.rs is missing from the Rust project.'

    metadata = subprocess.run(
        ['cargo', 'metadata', '--no-deps', '--format-version', '1'],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert metadata.returncode == 0, f'Invalid Cargo project: {metadata.stderr}'
    targets = [target for package in json.loads(metadata.stdout)['packages'] for target in package['targets']]
    assert any('bin' in target.get('kind', []) and target.get('name') == 'drift_monitor' for target in targets), \
        'Cargo project does not define the drift_monitor binary target.'

    assert os.path.isfile(BINARY), f'Release binary {BINARY} does not exist.'
    assert os.access(BINARY, os.X_OK), f'Release binary {BINARY} is not executable.'
    with open(BINARY, 'rb') as handle:
        assert handle.read(4) == b'\x7fELF', 'The release artifact is not a compiled ELF binary.'


def test_drift_report_mse():
    rows = [
        (1700000000, 'srv1', 1024),
        (1700000030, 'srv1', 1050),
        (1700000060, 'srv1', 1048),
        (1700000100, 'srv1', 1100),
        (1700000150, 'srv1', 1090),
        (1700000200, 'srv1', 1120),
        (1700000210, 'srv1', 1130),
        (1700000215, 'srv1', 1150),
        (1700000218, 'srv1', 1200),
    ]
    content = run_binary(rows)
    assert_matches_reference(content, rows)

    matches = re.findall(r'Rolling average config size: (\d+\.\d{2}) bytes', content)
    assert len(matches) == 5, f'Expected exactly 5 rolling average entries, found {len(matches)}.'

    expected = [1055.50, 1072.00, 1110.00, 1118.00, 1131.67]
    actual = [float(value) for value in matches]
    mse = sum((a - e) ** 2 for a, e in zip(actual, expected)) / len(expected)
    assert mse <= 0.01, f'MSE {mse} is greater than threshold 0.01. Actual values: {actual}'


def test_binary_on_unseen_input():
    window_size, threshold = read_spec()
    rng = random.SystemRandom()
    step_limit = max(1, window_size // (threshold + 2))
    timestamp = rng.randrange(1800000000, 1900000000)
    rows = []
    for _ in range(threshold + 8):
        timestamp += rng.randint(1, step_limit)
        rows.append((timestamp, 'srv-test', rng.randint(700, 2400)))

    expected = reference(rows)
    assert expected, 'Verifier-generated input unexpectedly produced no qualifying windows.'
    content = run_binary(rows)
    assert_matches_reference(content, rows)


def test_cron_job_setup():
    try:
        result = subprocess.run(
            ['crontab', '-l', '-u', 'user'],
            capture_output=True,
            text=True,
            check=True,
            timeout=20,
        )
        cron_output = result.stdout
    except subprocess.CalledProcessError:
        crontab_file = '/var/spool/cron/crontabs/user'
        if os.path.exists(crontab_file):
            with open(crontab_file, 'r') as handle:
                cron_output = handle.read()
        else:
            pytest.fail("Failed to retrieve crontab for 'user'.")

    assert BINARY in cron_output, 'Cron job for drift_monitor release binary is not set up correctly.'
    assert '* * * * *' in cron_output, 'Cron job is not scheduled to run every minute.'

    valid_entry = False
    for raw_line in cron_output.splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#') or '=' in line.split(None, 1)[0]:
            continue
        fields = line.split(None, 5)
        if len(fields) != 6 or fields[:5] != ['*', '*', '*', '*', '*']:
            continue
        try:
            command_tokens = shlex.split(fields[5])
        except ValueError:
            continue
        if BINARY in command_tokens:
            valid_entry = True
            break

    assert valid_entry, 'No active, valid every-minute cron entry executes the release binary.'
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), \
        'The binary referenced by the cron job is missing or not executable.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
