#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess

import pytest

PIPELINE_DIR = '/home/user/etl_pipeline'
RAW_LOGS = '/home/user/raw_logs.csv'
OUTPUT_FILE = '/home/user/aggregated_stats.csv'


def run_command(args, **kwargs):
    kwargs.setdefault('timeout', 20)
    return subprocess.run(args, **kwargs)


def test_deliverables_exist():
    """Check if all required deliverables are present."""
    expected_files = [
        '/home/user/etl_pipeline/clean_extract.c',
        '/home/user/etl_pipeline/aggregate.c',
        '/home/user/etl_pipeline/Makefile',
        '/home/user/etl_pipeline/run.sh'
    ]
    for f in expected_files:
        assert os.path.isfile(f), f"Missing deliverable: {f}"


def test_run_sh_executable():
    """Check if run.sh is executable."""
    assert os.access('/home/user/etl_pipeline/run.sh', os.X_OK), "/home/user/etl_pipeline/run.sh is not executable"


def test_pipeline_execution_and_output():
    """Compile, run the pipeline, and verify the original fixture output."""
    make_result = run_command(['make'], cwd=PIPELINE_DIR, capture_output=True, text=True)
    assert make_result.returncode == 0, f"make failed:\n{make_result.stderr}\n{make_result.stdout}"

    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    run_result = run_command(['./run.sh'], cwd=PIPELINE_DIR, capture_output=True, text=True)
    assert run_result.returncode == 0, f"run.sh failed:\n{run_result.stderr}\n{run_result.stdout}"
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} was not created by run.sh"

    with open(OUTPUT_FILE, 'r') as f:
        content = f.read().strip()

    expected = (
        "hour,total_events,error_count,avg_msg_len\n"
        "2023-10-15 14,3,1,23.33\n"
        "2023-10-15 15,2,1,17.00"
    )

    assert content.splitlines() == expected.splitlines(), (
        f"The output of the pipeline does not match the expected aggregated stats.\n"
        f"Expected:\n{expected}\n\nActual:\n{content}"
    )


def random_token(length):
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(length))


def make_dynamic_fixture():
    day = secrets.randbelow(20) + 1
    hours = sorted(secrets.SystemRandom().sample(range(24), 3))
    prefixes = [f"2025-07-{day:02d} {hour:02d}" for hour in hours]

    valid = [
        (prefixes[0], f"ERROR {random_token(secrets.randbelow(6) + 3)}"),
        (prefixes[0], f"plain,{random_token(secrets.randbelow(7) + 2)}"),
        (prefixes[1], f"lower error {random_token(secrets.randbelow(5) + 2)}"),
        (prefixes[1], f"{random_token(4)}ERROR{random_token(3)}"),
        (prefixes[1], f"ordinary {random_token(secrets.randbelow(6) + 2)}"),
        (prefixes[1], "ERROR at end"),
    ]

    rows = []
    second = 1
    for hour, message in valid:
        rows.append(f'{hour}:{second:02d}:00,10.0.0.{second},"{message}"')
        second += 1

    # Both records must be discarded in full. One belongs to an otherwise valid
    # hour and one is the only apparent record for its hour.
    rows.extend([
        f'{prefixes[0]}:40:00,192.0.2.10,"ERROR before newline\ncontinued {random_token(8)}"',
        f'{prefixes[2]}:41:00,192.0.2.11,"first line\nsecond line ERROR {random_token(8)}"',
    ])
    secrets.SystemRandom().shuffle(rows)
    csv_text = 'timestamp,ip_address,message\n' + '\n'.join(rows) + '\n'

    grouped = {}
    for hour, message in valid:
        count, errors, total_len = grouped.get(hour, (0, 0, 0))
        grouped[hour] = (
            count + 1,
            errors + (1 if 'ERROR' in message else 0),
            total_len + len(message),
        )

    expected_lines = ['hour,total_events,error_count,avg_msg_len']
    for hour in sorted(grouped):
        count, errors, total_len = grouped[hour]
        expected_lines.append(f'{hour},{count},{errors},{total_len / count:.2f}')
    return csv_text, expected_lines


def test_c_programs_process_unseen_input():
    """Exercise the compiled C stages on verifier-generated input."""
    csv_text, expected_lines = make_dynamic_fixture()

    clean = run_command(
        ['./clean_extract'], cwd=PIPELINE_DIR, input=csv_text,
        capture_output=True, text=True
    )
    assert clean.returncode == 0, f"clean_extract failed:\n{clean.stderr}"
    assert clean.stdout, "clean_extract produced no intermediate data"

    lines = clean.stdout.splitlines(keepends=True)
    env = os.environ.copy()
    env['LC_ALL'] = 'C'

    candidates = []
    sorted_all = run_command(['sort'], input=clean.stdout, capture_output=True, text=True, env=env)
    assert sorted_all.returncode == 0
    candidates.append(sorted_all.stdout)

    # Also allow an intermediate header convention where run.sh preserves the
    # first line and sorts only data records.
    if len(lines) > 1:
        sorted_tail = run_command(['sort'], input=''.join(lines[1:]), capture_output=True, text=True, env=env)
        assert sorted_tail.returncode == 0
        candidates.append(lines[0] + sorted_tail.stdout)

    failures = []
    for intermediate in candidates:
        aggregate = run_command(
            ['./aggregate'], cwd=PIPELINE_DIR, input=intermediate,
            capture_output=True, text=True
        )
        if aggregate.returncode == 0 and aggregate.stdout.strip().splitlines() == expected_lines:
            return
        failures.append(
            f"returncode={aggregate.returncode}\nstdout:\n{aggregate.stdout}\nstderr:\n{aggregate.stderr}"
        )

    pytest.fail(
        "The compiled clean_extract/sort/aggregate stages failed on unseen input.\n"
        f"Expected:\n{os.linesep.join(expected_lines)}\n\nAttempts:\n" + '\n---\n'.join(failures)
    )


def test_run_sh_processes_unseen_fixture():
    """Ensure orchestration reads the current raw_logs.csv rather than emitting fixed rows."""
    csv_text, expected_lines = make_dynamic_fixture()
    with open(RAW_LOGS, 'rb') as f:
        original = f.read()

    try:
        with open(RAW_LOGS, 'w', newline='') as f:
            f.write(csv_text)
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)

        result = run_command(['./run.sh'], cwd=PIPELINE_DIR, capture_output=True, text=True)
        assert result.returncode == 0, f"run.sh failed on unseen input:\n{result.stderr}\n{result.stdout}"
        assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} was not created by run.sh"

        with open(OUTPUT_FILE, 'r') as f:
            actual_lines = f.read().strip().splitlines()
        assert actual_lines == expected_lines, (
            "run.sh produced incorrect output for verifier-generated input.\n"
            f"Expected:\n{os.linesep.join(expected_lines)}\n\n"
            f"Actual:\n{os.linesep.join(actual_lines)}"
        )
    finally:
        with open(RAW_LOGS, 'wb') as f:
            f.write(original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
