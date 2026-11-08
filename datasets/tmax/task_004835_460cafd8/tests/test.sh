#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import re
import subprocess
import uuid
import pytest

CSV_PATH = "/home/user/config_ts.csv"
SCRIPT_PATH = "/home/user/extract_ts.py"
LOG_PATH = "/home/user/config_changes.log"

def test_csv_exists_and_content():
    """Verify that the CSV file is generated and contains the correct parsed data."""
    assert os.path.isfile(CSV_PATH), f"CSV file {CSV_PATH} was not created."

    expected_rows = [
        ['timestamp', 'normalized_key', 'value'],
        ['2023-10-01T12:00:00Z', 'network_setup', 'Interface eth0 up'],
        ['2023-10-01T12:05:00Z', 'database_connection', 'Retrying\ntimeout'],
        ['2023-10-01T12:10:00Z', 'firewall_rule', 'Block port 80'],
        ['2023-10-01T12:15:00Z', 'cache_servers', 'flushed\nall\nnodes']
    ]

    with open(CSV_PATH, 'r', encoding='utf-8') as f:
        reader = list(csv.reader(f))

    assert len(reader) == len(expected_rows), f"Expected {len(expected_rows)} rows in CSV, but found {len(reader)}."

    for i, (actual, expected) in enumerate(zip(reader, expected_rows)):
        assert actual == expected, f"Row {i+1} in CSV does not match expected.\nExpected: {expected}\nActual: {actual}"

def test_crontab_configured():
    """Verify that the crontab is configured to run the script every 15 minutes."""
    try:
        cron_out = subprocess.check_output(['crontab', '-l'], text=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Ensure a crontab is set for the user.")

    lines = cron_out.strip().split('\n')
    found_cron = False
    for line in lines:
        if line.startswith('#') or not line.strip():
            continue
        # Check if the line runs every 15 minutes
        parts = line.split()
        if len(parts) >= 6:
            minute_field = parts[0]
            is_15_mins = (minute_field == '*/15' or minute_field == '0,15,30,45')
            if is_15_mins and 'extract_ts.py' in line:
                found_cron = True
                break

    assert found_cron, "Could not find a crontab entry running extract_ts.py every 15 minutes (e.g., '*/15 * * * *')."

def test_script_exists_and_parses_dynamic_log():
    """Execute the submitted script against fresh data to prevent a hardcoded CSV."""
    assert os.path.isfile(SCRIPT_PATH), f"Python script {SCRIPT_PATH} does not exist."

    token = uuid.uuid4().hex
    records = [
        (
            '2041-02-03T04:05:06Z',
            f'  Feature {token}\n   Toggle\tName  ',
            f'  first {token} line\ncontinued\tvalue  '
        ),
        (
            '2041-02-03T04:20:06Z',
            f'\n Multi\tLine   KEY {token.upper()} \n',
            f'\nvalue with spaces {token}\nand another line\n'
        ),
        (
            '2041-02-03T04:35:06Z',
            f' Final   Setting {token} ',
            f' trailing record {token}\nwith embedded newline '
        )
    ]

    log_data = ''.join(
        f'[{timestamp}] USER: dynamic-user KEY: {key} VALUE: {value}\n'
        for timestamp, key, value in records
    )
    expected_rows = [['timestamp', 'normalized_key', 'value']]
    for timestamp, key, value in records:
        normalized_key = re.sub(r'\s+', '_', key.strip().lower())
        expected_rows.append([timestamp, normalized_key, value.strip()])

    with open(LOG_PATH, 'rb') as f:
        original_log = f.read()
    original_csv = None
    if os.path.exists(CSV_PATH):
        with open(CSV_PATH, 'rb') as f:
            original_csv = f.read()

    try:
        with open(LOG_PATH, 'w', encoding='utf-8', newline='') as f:
            f.write(log_data)
        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)

        result = subprocess.run(
            ['python3', SCRIPT_PATH],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15
        )
        assert result.returncode == 0, (
            f"Running {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(CSV_PATH), "The script did not generate config_ts.csv."

        with open(CSV_PATH, 'r', encoding='utf-8', newline='') as f:
            actual_rows = list(csv.reader(f))
        assert actual_rows == expected_rows, (
            f"The script did not correctly parse the dynamic multiline log.\n"
            f"Expected: {expected_rows!r}\nActual: {actual_rows!r}"
        )
    finally:
        with open(LOG_PATH, 'wb') as f:
            f.write(original_log)
        if original_csv is None:
            if os.path.exists(CSV_PATH):
                os.remove(CSV_PATH)
        else:
            with open(CSV_PATH, 'wb') as f:
                f.write(original_csv)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
