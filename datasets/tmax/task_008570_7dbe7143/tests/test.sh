#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import subprocess
from collections import Counter
from datetime import datetime
from pathlib import Path

PROJECT = Path('/home/user/etl_project')
LOGS = Path('/home/user/data/server_logs.txt')
USERS = Path('/home/user/data/users.csv')
SUMMARY = Path('/home/user/output/summary.csv')
PIPELINE_LOG = Path('/home/user/pipeline.log')

ORIGINAL_LOGS = '''[2024-03-15 08:14] U101 CONNECT IP:192.168.1.1
[2024-03-15 08:45] U102 DISCONNECT IP:10.0.0.5
[2024-03-15 08:50] U101 QUERY DB:SELECT_USERS
[2024-03-15 09:15] U999 INVALID NOTHING:HERE
[2024-03-15 10:05] U103 CONNECT IP:172.16.0.2
[2024-03-15 10:30] U101 ERROR TIMEOUT
'''

ORIGINAL_USERS = '''user_id,tier
U101,premium
U102,basic
U103,premium
U104,enterprise
'''

DYNAMIC_LOGS = '''[2024-03-15 08:01] U201 CONNECT IP:alpha
[2024-03-15 08:22] U201 RETRY IP:beta
[2024-03-15 08:59] U202 QUERY DB:items:recent
[2024-03-15 09:02] U203 ERROR TIMEOUT
[2024-03-15 09:03] U404 CONNECT IP:ignored
[2024-03-15 10:59] U204 CONNECT IP:omega
[2024-03-15 11:10] U201 FETCH API:v2
'''

DYNAMIC_USERS = '''user_id,tier
U201,gold
U202,silver
U203,gold
U204,bronze
'''


def cargo_environment():
    env = os.environ.copy()
    for cargo_home in (Path('/home/user/.cargo'), Path('/root/.cargo')):
        if (cargo_home / 'registry').exists():
            env['CARGO_HOME'] = str(cargo_home)
            env['HOME'] = str(cargo_home.parent)
            break
    return env


def run_pipeline():
    SUMMARY.parent.mkdir(parents=True, exist_ok=True)
    if SUMMARY.exists():
        SUMMARY.unlink()
    PIPELINE_LOG.write_text('VERIFIER PREEXISTING LINE\n')

    result = subprocess.run(
        ['cargo', 'run', '--quiet'],
        cwd=PROJECT,
        env=cargo_environment(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'cargo run failed with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert SUMMARY.is_file(), f'Output file {SUMMARY} does not exist after cargo run.'
    assert PIPELINE_LOG.is_file(), f'Log file {PIPELINE_LOG} does not exist after cargo run.'
    assert 'VERIFIER PREEXISTING LINE' in PIPELINE_LOG.read_text().splitlines(), (
        'The Rust program did not append to the existing pipeline log.'
    )


def read_summary():
    with SUMMARY.open('r', newline='') as f:
        return [row for row in csv.reader(f) if any(field.strip() for field in row)]


def derive_expected(users_text, logs_text):
    users = {}
    for row in csv.DictReader(users_text.splitlines()):
        users[row['user_id']] = row['tier']

    counts = Counter()
    valid = 0
    pattern = re.compile(r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2})\] (\S+) (\S+) (.+)$')
    for line in logs_text.splitlines():
        match = pattern.match(line)
        assert match, f'Invalid verifier fixture: {line}'
        timestamp, user_id, _action, payload = match.groups()
        if user_id not in users:
            continue
        valid += 1
        hour = datetime.strptime(timestamp, '%Y-%m-%d %H:%M').strftime('%Y-%m-%d %H:00')
        resource_type = payload.split(':', 1)[0]
        counts[(hour, users[user_id], resource_type)] += 1

    tiers = set(users.values())
    for hour in ('2024-03-15 08:00', '2024-03-15 09:00', '2024-03-15 10:00'):
        for tier in tiers:
            counts.setdefault((hour, tier, 'IP'), 0)

    rows = [['hour', 'tier', 'resource_type', 'count']]
    rows.extend([[hour, tier, resource, str(count)]
                 for (hour, tier, resource), count in sorted(counts.items())])
    return rows, valid


def test_rust_etl_pipeline():
    assert PROJECT.is_dir(), f'Rust project directory {PROJECT} does not exist.'
    assert (PROJECT / 'Cargo.toml').is_file(), 'Cargo.toml does not exist.'
    rust_sources = [p for p in (PROJECT / 'src').rglob('*.rs') if p.is_file()]
    assert rust_sources, 'No Rust source file exists under the project src directory.'
    assert any(p.stat().st_size > 0 for p in rust_sources), 'Rust source files are empty.'

    old_logs = LOGS.read_bytes()
    old_users = USERS.read_bytes()
    try:
        # Execute the submitted Rust project on the supplied data, then retain the
        # original verifier's exact output and log assertions.
        LOGS.write_text(ORIGINAL_LOGS)
        USERS.write_text(ORIGINAL_USERS)
        run_pipeline()

        expected_rows = [
            ['hour', 'tier', 'resource_type', 'count'],
            ['2024-03-15 08:00', 'basic', 'IP', '1'],
            ['2024-03-15 08:00', 'enterprise', 'IP', '0'],
            ['2024-03-15 08:00', 'premium', 'DB', '1'],
            ['2024-03-15 08:00', 'premium', 'IP', '1'],
            ['2024-03-15 09:00', 'basic', 'IP', '0'],
            ['2024-03-15 09:00', 'enterprise', 'IP', '0'],
            ['2024-03-15 09:00', 'premium', 'IP', '0'],
            ['2024-03-15 10:00', 'basic', 'IP', '0'],
            ['2024-03-15 10:00', 'enterprise', 'IP', '0'],
            ['2024-03-15 10:00', 'premium', 'IP', '1'],
            ['2024-03-15 10:00', 'premium', 'TIMEOUT', '1'],
        ]
        actual_rows = read_summary()
        assert len(actual_rows) == len(expected_rows), (
            f'Expected {len(expected_rows)} rows in summary.csv, got {len(actual_rows)}.'
        )
        for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
            assert actual == expected, f'Row {i+1} mismatch. Expected {expected}, got {actual}.'

        expected_log_line = 'ETL SUCCESS: Processed 5 valid log entries'
        lines = PIPELINE_LOG.read_text().splitlines()
        assert any(expected_log_line in line for line in lines), (
            f"Expected log line '{expected_log_line}' not found in {PIPELINE_LOG}."
        )

        # Re-run on verification-only inputs and derive the expected answer from
        # those inputs, preventing a submission that merely writes the known files.
        LOGS.write_text(DYNAMIC_LOGS)
        USERS.write_text(DYNAMIC_USERS)
        dynamic_expected, valid_count = derive_expected(DYNAMIC_USERS, DYNAMIC_LOGS)
        run_pipeline()

        assert read_summary() == dynamic_expected, (
            'summary.csv was not correctly derived from the verification inputs.'
        )
        dynamic_log_line = f'ETL SUCCESS: Processed {valid_count} valid log entries'
        assert dynamic_log_line in PIPELINE_LOG.read_text().splitlines(), (
            f"Expected exact log line '{dynamic_log_line}' after the verification run."
        )
    finally:
        LOGS.write_bytes(old_logs)
        USERS.write_bytes(old_users)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
