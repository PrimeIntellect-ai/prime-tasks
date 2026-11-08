#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import re
import pytest

# Immutable oracle derived from the dataset installed by setup.sh. This prevents
# agent-writable source files from being emptied or changed to weaken the oracle.
IMMUTABLE_EXPECTED_DATA = [
    {"server_id": "srv-alpha", "change_timestamp": "2023-11-01 09:00:00"},
    {"server_id": "srv-gamma", "change_timestamp": "2023-11-01 10:30:00"},
]

def get_expected_changepoints():
    # 1. Read server metadata to find prod servers
    prod_servers = set()
    meta_path = "/home/user/server_meta.csv"
    if os.path.exists(meta_path):
        with open(meta_path, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get("environment") == "prod":
                    prod_servers.add(row.get("server_id"))

    # 2. Parse and deduplicate logs
    log_path = "/home/user/raw_configs.log"
    log_pattern = re.compile(r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] (\S+) (\S+) (\S+)=(.*)$')

    parsed_logs = set()
    if os.path.exists(log_path):
        with open(log_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                match = log_pattern.match(line)
                if match:
                    timestamp, server_id, ip, key, value = match.groups()
                    if key == "SSH_ROOT_LOGIN":
                        parsed_logs.add((timestamp, server_id, value))

    # 3. Sort logs by timestamp to process chronologically
    sorted_logs = sorted(list(parsed_logs), key=lambda x: x[0])

    # 4. Find changepoints
    server_states = {}
    changepoints = {}

    for timestamp, server_id, value in sorted_logs:
        if server_id not in prod_servers:
            continue

        prev_state = server_states.get(server_id)
        if prev_state == "no" and value == "yes":
            if server_id not in changepoints:
                changepoints[server_id] = timestamp

        server_states[server_id] = value

    # 5. Format and sort expected output
    expected_rows = [{"server_id": sid, "change_timestamp": ts} for sid, ts in changepoints.items()]
    expected_rows.sort(key=lambda x: x["server_id"])
    return expected_rows

def test_changepoints_file_exists():
    file_path = "/home/user/changepoints.csv"
    assert os.path.exists(file_path), f"Output file {file_path} is missing. The script did not generate it."
    assert os.path.isfile(file_path), f"{file_path} is not a valid file."

def test_changepoints_content():
    file_path = "/home/user/changepoints.csv"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."

    expected_data = get_expected_changepoints()

    actual_data = []
    with open(file_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"File {file_path} is empty. Expected header and data.")

        assert header == ["server_id", "change_timestamp"], \
            f"Incorrect header in {file_path}. Expected ['server_id', 'change_timestamp'], got {header}"

        for row in reader:
            if not row:
                continue
            assert len(row) == 2, f"Malformed row in {file_path}: {row}"
            actual_data.append({"server_id": row[0], "change_timestamp": row[1]})

    # Check sorting
    actual_server_ids = [row["server_id"] for row in actual_data]
    assert actual_server_ids == sorted(actual_server_ids), \
        f"Rows in {file_path} are not sorted alphabetically by server_id."

    # Check against an oracle that cannot be changed through /home/user inputs.
    assert actual_data == IMMUTABLE_EXPECTED_DATA, \
        f"Data in {file_path} does not match the required changepoints.\nExpected: {IMMUTABLE_EXPECTED_DATA}\nActual: {actual_data}"

    # Preserve the original recomputed exact-content check.
    assert actual_data == expected_data, \
        f"Data in {file_path} does not match expected output.\nExpected: {expected_data}\nActual: {actual_data}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
