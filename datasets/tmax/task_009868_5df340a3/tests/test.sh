#!/bin/bash
set -o pipefail
mkdir -p /logs/verifier

run_checks() {
    test -f /home/user/analyze.c || return 1
    test -f /home/user/analyze || return 1
    test -x /home/user/analyze || return 1

    python3 - <<'PY' || return 1
from pathlib import Path
p = Path('/home/user/analyze')
assert p.read_bytes()[:4] == b'\x7fELF', 'Expected /home/user/analyze to be a compiled ELF executable.'
PY

    gcc -std=c11 -Wall -Wextra /home/user/analyze.c -o /home/user/analyze || return 1
    test -x /home/user/analyze || return 1

    rm -f /home/user/anomalies.csv
    timeout 10s /home/user/analyze || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_anomalies_file_exists():
    """Test if the output CSV file was created."""
    path = "/home/user/anomalies.csv"
    assert os.path.isfile(path), f"Expected output file {path} is missing."

def test_anomalies_file_content():
    """Test if the output CSV file has the correct computed content."""
    path = "/home/user/anomalies.csv"
    if not os.path.isfile(path):
        pytest.fail(f"File {path} does not exist.")

    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "bucket_start,total_impact,moving_avg,is_anomaly",
        "1700002800,30,0.00,0",
        "1700006400,40,30.00,0",
        "1700010000,20,35.00,0",
        "1700013600,70,30.00,1",
        "1700017200,10,43.33,0",
        "1700020800,0,33.33,0",
        "1700024400,60,26.67,1"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in anomalies.csv, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Mismatch at line {i+1}: expected '{expected}', got '{actual}'."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    cat << 'DYNAMIC_EOF' > /tmp/test_dynamic.py
import os
import random
import secrets
import subprocess
from pathlib import Path

INPUT = Path('/home/user/config_changes.csv')
OUTPUT = Path('/home/user/anomalies.csv')
PROGRAM = '/home/user/analyze'


def expected_output(events):
    totals = {}
    for timestamp, _server, impact in events:
        bucket = timestamp - (timestamp % 3600)
        totals[bucket] = totals.get(bucket, 0) + impact

    first = min(totals)
    last = max(totals)
    buckets = list(range(first, last + 3600, 3600))
    values = [totals.get(bucket, 0) for bucket in buckets]
    lines = ['bucket_start,total_impact,moving_avg,is_anomaly']

    for i, (bucket, total) in enumerate(zip(buckets, values)):
        previous = values[max(0, i - 3):i]
        moving_average = sum(previous) / len(previous) if previous else 0.0
        anomaly = int(total > 2.0 * moving_average and total > 50)
        lines.append(f'{bucket},{total},{moving_average:.2f},{anomaly}')
    return lines


def run_case(events):
    INPUT.write_text(''.join(f'{ts},{server},{impact}\n' for ts, server, impact in events))
    if OUTPUT.exists():
        OUTPUT.unlink()

    result = subprocess.run(
        [PROGRAM], cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f'program exited with {result.returncode}; stderr: {result.stderr}'
    )
    assert OUTPUT.is_file(), 'Program did not create /home/user/anomalies.csv'
    actual = [line.strip() for line in OUTPUT.read_text().splitlines() if line.strip()]
    assert actual == expected_output(events)


def test_program_processes_varied_inputs():
    base = 1800000000 - (1800000000 % 3600)
    cases = [
        [
            (base + 7200 + 17, 'gamma', 61),
            (base + 33, 'alpha', 20),
            (base + 3600 + 200, 'beta', 60),
            (base + 180, 'alpha', 31),
        ],
        [
            (base + 5 * 3600 + 9, 'last', 52),
            (base + 8, 'first', 51),
            (base + 2 * 3600 + 1, 'middle', 5),
            (base + 5 * 3600 + 100, 'last', 10),
        ],
    ]

    rng = random.Random(secrets.randbits(128))
    for case_number in range(4):
        span = rng.randint(7, 14)
        events = []
        for bucket_index in range(span):
            count = rng.randint(0, 3)
            for event_index in range(count):
                events.append((
                    base + case_number * 30 * 3600 + bucket_index * 3600 + rng.randrange(3600),
                    f'srv-{case_number}-{event_index}',
                    rng.randint(0, 90),
                ))
        if not events:
            events.append((base + case_number * 30 * 3600, 'fallback', 1))
        events.append((base + case_number * 30 * 3600 + 1, 'boundary-first', rng.randint(1, 80)))
        events.append((base + case_number * 30 * 3600 + (span - 1) * 3600 + 3599,
                       'boundary-last', rng.randint(1, 80)))
        rng.shuffle(events)
        cases.append(events)

    for events in cases:
        run_case(events)
DYNAMIC_EOF

    python3 -m pytest /tmp/test_dynamic.py -x --tb=short || return 1
}

if run_checks 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
