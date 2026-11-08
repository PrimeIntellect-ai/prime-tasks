#!/bin/bash
set -u
mkdir -p /logs/verifier

run_checks() {
    PROJECT=/home/user/strict_etl
    MANIFEST="$PROJECT/Cargo.toml"
    BINARY="$PROJECT/target/debug/strict_etl"

    [ -d "$PROJECT" ] || { echo 'Missing Rust project directory' >&2; return 1; }
    [ -f "$MANIFEST" ] || { echo 'Missing Cargo.toml' >&2; return 1; }
    find "$PROJECT" -path "$PROJECT/target" -prune -o -type f -name '*.rs' -size +0c -print | grep -q . || {
        echo 'No non-empty Rust source file found' >&2
        return 1
    }

    /usr/bin/cargo build --manifest-path "$MANIFEST" || return 1
    [ -x "$BINARY" ] || { echo 'Compiled strict_etl binary not found' >&2; return 1; }

    PROJECT="$PROJECT" BINARY="$BINARY" python3 - <<'PY' || return 1
import csv
import os
import random
import subprocess
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

project = Path(os.environ['PROJECT'])
binary = os.environ['BINARY']
users_path = Path('/home/user/data/users.csv')
events_path = Path('/home/user/data/events.csv')
output_path = Path('/home/user/pipeline_out/dataset.csv')

original_users = users_path.read_bytes()
original_events = events_path.read_bytes()


def rounded_score(value):
    return str(int((Decimal(value) * Decimal(10)).to_integral_value(rounding=ROUND_HALF_UP)))


def run_case(case_number):
    rng = random.SystemRandom()
    user_ids = rng.sample(range(200, 9000), 4)
    event_ids = rng.sample(range(10, 9900), 6)
    token = rng.randrange(100000, 999999)

    users = [
        [user_ids[0], 31 + case_number, f'web{token}'],
        [user_ids[1], '', f'app{token}'],
        [user_ids[2], 0, f'ref{token}'],
        [user_ids[3], '', f'other{token}'],
    ]
    rng.shuffle(users)

    scores = ['2.26', '8.14', '0.06', '4.44', '6.37']
    events = [
        [event_ids[0], user_ids[1], scores[0]],
        [event_ids[1], user_ids[0], scores[1]],
        [event_ids[2], user_ids[3], scores[2]],
        [event_ids[3], user_ids[1], scores[3]],
        [event_ids[4], user_ids[2], scores[4]],
        [event_ids[5], rng.randrange(10000, 20000), '9.91'],
    ]
    rng.shuffle(events)

    with users_path.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['user_id', 'age', 'signup_source'])
        writer.writerows(users)

    with events_path.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['event_id', 'user_id', 'score'])
        writer.writerows(events)

    if output_path.exists():
        output_path.unlink()

    subprocess.run([binary], cwd=project, check=True, timeout=30)
    assert output_path.is_file(), 'Rust program did not create dataset.csv'

    user_map = {
        int(row[0]): ('0' if row[1] == '' else str(int(row[1])), row[2])
        for row in users
    }
    expected = []
    for event_id, user_id, score in events:
        if int(user_id) in user_map:
            age, source = user_map[int(user_id)]
            expected.append([
                str(int(event_id)), str(int(user_id)), age, source,
                rounded_score(score),
            ])
    expected.sort(key=lambda row: int(row[0]))

    with output_path.open(newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        actual = list(reader)

    assert header == ['event_id', 'user_id', 'age', 'signup_source', 'score_normalized'], header
    assert actual == expected, f'Dynamic case {case_number} failed: expected {expected}, got {actual}'
    for row in actual:
        assert '.' not in row[2], f'age was emitted as a non-integer: {row[2]}'
        assert '.' not in row[4], f'score_normalized was emitted as a non-integer: {row[4]}'


try:
    run_case(1)
    run_case(2)
finally:
    users_path.write_bytes(original_users)
    events_path.write_bytes(original_events)

if output_path.exists():
    output_path.unlink()
subprocess.run([binary], cwd=project, check=True, timeout=30)
PY

    cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_output_file_exists():
    assert os.path.isfile("/home/user/pipeline_out/dataset.csv"), "Output file /home/user/pipeline_out/dataset.csv does not exist"

def test_output_file_content():
    expected_lines = [
        "event_id,user_id,age,signup_source,score_normalized",
        "101,1,25,web,55",
        "102,2,0,app,32",
        "103,2,0,app,81",
        "104,3,40,web,99",
        "105,4,0,app,10"
    ]

    with open("/home/user/pipeline_out/dataset.csv", "r") as f:
        # Read lines, strip whitespace/newlines, filter out empty lines
        actual_lines = [line.strip().replace(" ", "") for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines, but got {len(actual_lines)}"

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} does not match expected output. Expected: '{expected}', Actual: '{actual}'"
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
