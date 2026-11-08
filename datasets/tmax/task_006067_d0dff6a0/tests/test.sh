#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
SRC = HOME / 'src'
ANALYZER = HOME / 'bin' / 'analyzer'
PIPELINE = HOME / 'pipeline.sh'
CSV = HOME / 'resource_usage.csv'
MAILDIR = HOME / 'alerts_mail'

ORIGINAL_CSV = b'''2023-10-01T10:00:00Z,80,60
2023-10-01T10:05:00Z,90,92
2023-10-01T10:10:00Z,50,80
2023-10-01T10:15:00Z,85,84
'''


@pytest.fixture(scope='session', autouse=True)
def restore_resource_csv():
    old = CSV.read_bytes() if CSV.exists() else None
    yield
    if old is None:
        CSV.unlink(missing_ok=True)
    else:
        CSV.write_bytes(old)


def expected_output(rows):
    average_cpu = sum(cpu for _, cpu, _ in rows) // len(rows)
    maximum_memory = max(memory for _, _, memory in rows)
    output = ''
    if average_cpu > 75:
        output += 'ALERT_CPU_HIGH\n'
    if maximum_memory > 85:
        output += 'ALERT_MEM_HIGH\n'
    return output


def csv_bytes(rows):
    return ''.join(f'{timestamp},{cpu},{memory}\n' for timestamp, cpu, memory in rows).encode()


def random_rows(kind, count=7):
    rng = secrets.SystemRandom()
    rows = []
    for i in range(count):
        if kind in ('cpu', 'both'):
            cpu = rng.randint(76, 100)
        else:
            cpu = rng.randint(0, 75)

        if kind in ('mem', 'both') and i == rng.randrange(count):
            memory = rng.randint(86, 100)
        else:
            memory = rng.randint(0, 85)
        rows.append((f'run-{secrets.token_hex(5)}-{i}', cpu, memory))

    if kind in ('mem', 'both') and max(row[2] for row in rows) <= 85:
        timestamp, cpu, _ = rows[-1]
        rows[-1] = (timestamp, cpu, rng.randint(86, 100))
    return rows


def test_pipeline_exists_and_executable():
    assert PIPELINE.is_file(), f'{PIPELINE} does not exist.'
    assert os.access(PIPELINE, os.X_OK), f'{PIPELINE} is not executable.'


def test_analyzer_source_build_and_dynamic_behavior(tmp_path):
    assert (SRC / 'analyzer.cpp').is_file(), '/home/user/src/analyzer.cpp does not exist.'
    assert (SRC / 'Makefile').is_file(), '/home/user/src/Makefile does not exist.'

    ANALYZER.unlink(missing_ok=True)
    result = subprocess.run(
        ['make', '-C', str(SRC)], capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f'Make failed:\n{result.stderr}'
    assert ANALYZER.is_file(), 'Make did not create /home/user/bin/analyzer.'
    assert os.access(ANALYZER, os.X_OK), 'Built analyzer is not executable.'
    assert ANALYZER.read_bytes()[:4] == b'\x7fELF', 'Built analyzer is not a compiled executable.'

    before = ANALYZER.stat().st_mtime_ns
    make_result = subprocess.run(
        ['make', '-C', str(SRC)], capture_output=True, text=True, timeout=30
    )
    assert make_result.returncode == 0, 'Make failed on second run.'
    output_lower = make_result.stdout.lower()
    assert 'up to date' in output_lower or 'nothing to be done' in output_lower, \
        f'Makefile is not idempotent. Output: {make_result.stdout}'
    assert ANALYZER.stat().st_mtime_ns == before, 'Analyzer was recompiled without a source change.'

    rng = secrets.SystemRandom()
    cases = [random_rows(kind, rng.randint(3, 11)) for kind in ('none', 'cpu', 'mem', 'both')]
    for _ in range(6):
        cases.append([
            (f'dynamic-{secrets.token_hex(6)}-{i}', rng.randint(0, 100), rng.randint(0, 100))
            for i in range(rng.randint(2, 12))
        ])

    for index, rows in enumerate(cases):
        input_path = tmp_path / f'usage-{index}-{secrets.token_hex(4)}.csv'
        input_path.write_bytes(csv_bytes(rows))
        run = subprocess.run(
            [str(ANALYZER), str(input_path)], capture_output=True, text=True, timeout=10
        )
        assert run.returncode == 0, f'Analyzer failed for dynamic input: {run.stderr}'
        assert run.stdout == expected_output(rows), \
            f'Incorrect analyzer output for rows {rows!r}: {run.stdout!r}'


def test_pipeline_execution_and_results():
    fixed_rows = [
        ('2023-10-01T10:00:00Z', 80, 60),
        ('2023-10-01T10:05:00Z', 90, 92),
        ('2023-10-01T10:10:00Z', 50, 80),
        ('2023-10-01T10:15:00Z', 85, 84),
    ]
    cases = [('fixed', fixed_rows)]
    cases.extend((kind, random_rows(kind)) for kind in ('none', 'cpu', 'mem', 'both'))

    for name, rows in cases:
        CSV.write_bytes(ORIGINAL_CSV if name == 'fixed' else csv_bytes(rows))
        shutil.rmtree(MAILDIR, ignore_errors=True)
        ANALYZER.unlink(missing_ok=True)

        result = subprocess.run([str(PIPELINE)], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, \
            f'pipeline.sh failed with return code {result.returncode}\nStderr: {result.stderr}'

        for directory in ('new', 'cur', 'tmp'):
            path = MAILDIR / directory
            assert path.is_dir(), f'Maildir directory {path} was not created.'

        assert ANALYZER.is_file() and os.access(ANALYZER, os.X_OK), \
            'Pipeline did not build the analyzer.'

        make_result = subprocess.run(
            ['make', '-C', str(SRC)], capture_output=True, text=True, timeout=30
        )
        assert make_result.returncode == 0, 'Make failed on second run.'
        output_lower = make_result.stdout.lower()
        assert 'up to date' in output_lower or 'nothing to be done' in output_lower, \
            f'Makefile is not idempotent. Output: {make_result.stdout}'

        alerts = expected_output(rows)
        message = MAILDIR / 'new' / 'latest_alert.msg'
        if not alerts:
            assert not message.exists(), 'Pipeline created an alert email when analyzer output was empty.'
            continue

        assert message.is_file(), f'Alert message {message} was not created.'
        expected_message = (
            'To: capacity-team@local.domain\n'
            'From: planner-bot@local.domain\n'
            'Subject: Capacity Alert\n'
            '\n'
            + alerts
        ).encode()
        content = message.read_bytes()
        assert content == expected_message, \
            f'Email does not have the required exact format. Got: {content!r}'

        # Preserve the original fixed-input alert assertions explicitly.
        if name == 'fixed':
            text = content.decode()
            assert 'To: capacity-team@local.domain' in text
            assert 'From: planner-bot@local.domain' in text
            assert 'Subject: Capacity Alert' in text
            assert 'ALERT_CPU_HIGH' in text
            assert 'ALERT_MEM_HIGH' in text
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
