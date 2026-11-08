#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import csv
import subprocess
import pytest
from pathlib import Path

RAW_LOGS_DIR = "/home/user/raw_logs"
OUTPUT_DIR = "/home/user/output"
PROCESS_SCRIPT = "/home/user/process_configs.sh"
LATEST_SCRIPT = "/home/user/latest_state.sh"
CONFIG_STATE_CSV = "/home/user/output/config_state.csv"
LATEST_STATE_CSV = "/home/user/output/latest_state.csv"
CRON_FILE = "/home/user/cron_schedule.txt"

LOG_PATTERN = re.compile(r'^\[(?P<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\] (?P<server>\S+) - ACTION: (?P<action>\S+) - KEY: (?P<key>\S+) - VALUE: (?P<value>.*)$')

def get_expected_config_state():
    records = set()
    for log_file in Path(RAW_LOGS_DIR).glob("*.log"):
        with open(log_file, "r") as f:
            for line in f:
                match = LOG_PATTERN.match(line.strip())
                if match:
                    records.add(match.groups())

    # Sort chronologically, then by server, then by key
    sorted_records = sorted(records, key=lambda x: (x[0], x[1], x[3]))
    return [("timestamp", "server", "action", "key", "value")] + sorted_records

def get_expected_latest_state(config_state_records):
    # config_state_records includes header
    latest_map = {}
    for record in config_state_records[1:]:
        timestamp, server, action, key, value = record
        # Since config_state_records is sorted chronologically, the last one seen for a (server, key) is the latest
        latest_map[(server, key)] = record

    # Sort by server, then by key
    sorted_latest = sorted(latest_map.values(), key=lambda x: (x[1], x[3]))
    return [("timestamp", "server", "action", "key", "value")] + sorted_latest

def test_process_configs_script_exists_and_runs():
    assert os.path.isfile(PROCESS_SCRIPT), f"Script {PROCESS_SCRIPT} does not exist."
    assert os.access(PROCESS_SCRIPT, os.X_OK), f"Script {PROCESS_SCRIPT} is not executable."

    result = subprocess.run([PROCESS_SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, f"{PROCESS_SCRIPT} failed to execute properly. Stderr: {result.stderr}"

def test_config_state_csv_correctness():
    assert os.path.isfile(CONFIG_STATE_CSV), f"Output file {CONFIG_STATE_CSV} was not created."

    with open(CONFIG_STATE_CSV, "r") as f:
        reader = csv.reader(f)
        actual_records = [tuple(row) for row in reader]

    expected_records = get_expected_config_state()

    assert actual_records == expected_records, f"The contents of {CONFIG_STATE_CSV} do not match the expected deduplicated and sorted output."

def test_latest_state_script_exists_and_runs():
    assert os.path.isfile(LATEST_SCRIPT), f"Script {LATEST_SCRIPT} does not exist."
    assert os.access(LATEST_SCRIPT, os.X_OK), f"Script {LATEST_SCRIPT} is not executable."

    result = subprocess.run([LATEST_SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, f"{LATEST_SCRIPT} failed to execute properly. Stderr: {result.stderr}"

def test_latest_state_csv_correctness():
    assert os.path.isfile(LATEST_STATE_CSV), f"Output file {LATEST_STATE_CSV} was not created."

    with open(LATEST_STATE_CSV, "r") as f:
        reader = csv.reader(f)
        actual_records = [tuple(row) for row in reader]

    expected_config = get_expected_config_state()
    expected_records = get_expected_latest_state(expected_config)

    assert actual_records == expected_records, f"The contents of {LATEST_STATE_CSV} do not match the expected latest state output."

def test_cron_schedule():
    assert os.path.isfile(CRON_FILE), f"Cron schedule file {CRON_FILE} does not exist."

    with open(CRON_FILE, "r") as f:
        content = f.read().strip()

    # Check for */5 * * * * and the script path. Allow optional 'user' field.
    assert "*/5 * * * *" in content, "Cron expression does not schedule for every 5 minutes (missing '*/5 * * * *')."
    assert PROCESS_SCRIPT in content, f"Cron expression does not contain the script path {PROCESS_SCRIPT}."

    # Ensure it's a single line or valid format
    lines = [line for line in content.split('\n') if line.strip() and not line.strip().startswith('#')]
    assert len(lines) == 1, "Cron schedule file should contain exactly one active cron expression line."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
