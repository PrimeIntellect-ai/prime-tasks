#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import calendar
import csv
import datetime
import json
import os
import secrets
import subprocess
import sys
import pytest

SCRIPT = '/home/user/process_pcap_logs.py'
CSV_PATH = '/home/user/pcap_logs.csv'
OUTPUT_PATH = '/home/user/binned_stats.json'

EXPECTED_CSV = b'''id,timestamp,bytes\n1,2024-01-30T14:22:00Z,500\n2,2024-01-30T15:22:00Z,600\n3,2024-01-31T23:30:00Z,700\n4,2024-02-01T10:00:00Z,800\n5,2024-02-29T18:15:00Z,900\n'''

def run_script():
    try:
        return subprocess.run(
            [sys.executable, SCRIPT],
            cwd='/home/user',
            capture_output=True,
            text=True,
            timeout=8,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('process_pcap_logs.py did not complete within 8 seconds')

def expected_next_midnight(timestamp):
    dt = datetime.datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
    next_date = dt.date() + datetime.timedelta(days=1)
    return datetime.datetime.combine(
        next_date, datetime.time.min, tzinfo=datetime.timezone.utc
    ).isoformat()

def test_repaired_function_and_executable():
    assert os.path.isfile(SCRIPT), f'{SCRIPT} is missing'
    with open(CSV_PATH, 'rb') as f:
        original_csv = f.read()
    assert original_csv == EXPECTED_CSV, 'The input CSV file was changed'

    # Exercise get_next_midnight directly on month, leap-year, year, and
    # unpredictable valid-date rollovers. Expected values are independently
    # calculated by the verifier.
    timestamps = [
        '2023-12-31T23:59:59Z',
        '2024-01-31T12:34:56Z',
        '2024-02-29T18:15:00Z',
        '2100-02-28T00:00:00Z',
        '2024-06-30T01:02:03+00:00',
    ]
    for _ in range(20):
        year = 1990 + secrets.randbelow(150)
        month = 1 + secrets.randbelow(12)
        day = 1 + secrets.randbelow(calendar.monthrange(year, month)[1])
        hour = secrets.randbelow(24)
        minute = secrets.randbelow(60)
        second = secrets.randbelow(60)
        timestamps.append(
            f'{year:04d}-{month:02d}-{day:02d}T{hour:02d}:{minute:02d}:{second:02d}Z'
        )

    cases = [[ts, expected_next_midnight(ts)] for ts in timestamps]
    child_code = r'''
import importlib.util
import json
import sys
spec = importlib.util.spec_from_file_location('submitted_process_pcap_logs', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert callable(getattr(module, 'get_next_midnight', None)), 'get_next_midnight is missing or not callable'
for timestamp, expected in json.loads(sys.argv[2]):
    actual = module.get_next_midnight(timestamp)
    assert actual == expected, f'get_next_midnight({timestamp!r}) returned {actual!r}, expected {expected!r}'
'''
    try:
        direct = subprocess.run(
            [sys.executable, '-c', child_code, SCRIPT, json.dumps(cases)],
            capture_output=True,
            text=True,
            timeout=8,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('get_next_midnight did not complete within 8 seconds')
    assert direct.returncode == 0, direct.stdout + direct.stderr

    # Replace the CSV only during verification with unpredictable records to
    # prove that the executable actually reads and aggregates its input rather
    # than merely writing the ticket's known output. Restore it afterward.
    dynamic_rows = []
    for idx, timestamp in enumerate(timestamps[:12], 1):
        dynamic_rows.append((str(idx), timestamp, str(100 + idx)))
    dynamic_rows.extend([
        ('1001', timestamps[0], '999'),
        ('1002', timestamps[1], '998'),
    ])
    dynamic_expected = {}
    for _, timestamp, _ in dynamic_rows:
        key = expected_next_midnight(timestamp)
        dynamic_expected[key] = dynamic_expected.get(key, 0) + 1

    try:
        with open(CSV_PATH, 'w', newline='') as f:
            writer = csv.writer(f, lineterminator='\n')
            writer.writerow(['id', 'timestamp', 'bytes'])
            writer.writerows(dynamic_rows)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        dynamic_run = run_script()
        assert dynamic_run.returncode == 0, dynamic_run.stdout + dynamic_run.stderr
        assert os.path.isfile(OUTPUT_PATH), 'The script did not create binned_stats.json'
        with open(OUTPUT_PATH, 'r') as f:
            dynamic_data = json.load(f)
        assert dynamic_data == dynamic_expected, (
            f'The executed script did not aggregate the supplied CSV correctly. '
            f'Expected: {dynamic_expected}, Got: {dynamic_data}'
        )
    finally:
        with open(CSV_PATH, 'wb') as f:
            f.write(original_csv)

    # Run the repaired artifact on the real ticket input and leave its output
    # in place for the original final-state assertions below.
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    final_run = run_script()
    assert final_run.returncode == 0, final_run.stdout + final_run.stderr

def test_binned_stats_exists():
    """Verify that the output JSON file was successfully created."""
    file_path = '/home/user/binned_stats.json'
    assert os.path.isfile(file_path), f"Output file {file_path} was not created. Did the script run successfully?"

def test_binned_stats_content():
    """Verify that the output JSON file contains the correctly calculated next-midnight bins."""
    file_path = '/home/user/binned_stats.json'

    # Expected result derived from the input CSV:
    # 2024-01-30 -> next midnight is 2024-01-31 (2 entries)
    # 2024-01-31 -> next midnight is 2024-02-01 (1 entry)
    # 2024-02-01 -> next midnight is 2024-02-02 (1 entry)
    # 2024-02-29 -> next midnight is 2024-03-01 (1 entry)
    expected_output = {
        "2024-01-31T00:00:00+00:00": 2,
        "2024-02-01T00:00:00+00:00": 1,
        "2024-02-02T00:00:00+00:00": 1,
        "2024-03-01T00:00:00+00:00": 1
    }

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} does not contain valid JSON.")

    assert data == expected_output, (
        f"The contents of {file_path} do not match the expected aggregated data. "
        f"Expected: {expected_output}, Got: {data}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
