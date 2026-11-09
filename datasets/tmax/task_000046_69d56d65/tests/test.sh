#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
from collections import Counter
from datetime import datetime, timedelta
from sklearn.model_selection import train_test_split

PROCESSED_FILE = "/home/user/processed_full.csv"
SAMPLED_FILE = "/home/user/sampled_configs.csv"
INPUT_FILE = "/home/user/config_changes.jsonl"
EXPECTED_COLUMNS = ["timestamp", "server_id", "role", "ip_address", "config_val"]


def get_expected_resampled_data():
    if not os.path.exists(INPUT_FILE):
        return []

    with open(INPUT_FILE, "r") as f:
        data = [json.loads(line) for line in f]

    servers = {}
    for row in data:
        sid = row["server_id"]
        if sid not in servers:
            servers[sid] = []
        servers[sid].append(row)

    expected_rows = []
    for sid, rows in servers.items():
        rows.sort(key=lambda x: x["timestamp"])
        min_dt = datetime.fromisoformat(rows[0]["timestamp"])
        max_dt = datetime.fromisoformat(rows[-1]["timestamp"])

        current_dt = min_dt
        while current_dt <= max_dt:
            past_records = [r for r in rows if datetime.fromisoformat(r["timestamp"]) <= current_dt]
            if past_records:
                record = past_records[-1]
            else:
                record = rows[0]

            ip_parts = record["ip_address"].split(".")
            ip_parts[-1] = "XXX"
            masked_ip = ".".join(ip_parts)

            expected_rows.append({
                "timestamp": current_dt.isoformat(),
                "server_id": sid,
                "role": record["role"],
                "ip_address": masked_ip,
                "config_val": str(record["config_val"]),
            })
            current_dt += timedelta(hours=1)

    return expected_rows


def row_key(row):
    return tuple(row[column] for column in EXPECTED_COLUMNS)


def test_processed_full_exists():
    assert os.path.exists(PROCESSED_FILE), f"The file {PROCESSED_FILE} does not exist."


def test_processed_full_content():
    assert os.path.exists(PROCESSED_FILE), f"The file {PROCESSED_FILE} does not exist."

    with open(PROCESSED_FILE, "r", newline="") as f:
        reader = csv.DictReader(f)
        actual_rows = list(reader)

    expected_rows = get_expected_resampled_data()

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in {PROCESSED_FILE}, found {len(actual_rows)}."
    assert reader.fieldnames == EXPECTED_COLUMNS, f"Expected columns {EXPECTED_COLUMNS}, found {reader.fieldnames}."

    for row in actual_rows:
        assert row["ip_address"].endswith(".XXX"), f"IP address {row['ip_address']} is not properly masked."

    for expected in expected_rows:
        match = next((r for r in actual_rows if r["server_id"] == expected["server_id"] and r["timestamp"] == expected["timestamp"]), None)
        assert match is not None, f"Missing expected row for server {expected['server_id']} at {expected['timestamp']}."
        assert match["role"] == expected["role"], f"Expected role {expected['role']} for {expected['server_id']} at {expected['timestamp']}, found {match['role']}."
        assert match["config_val"] == expected["config_val"], f"Expected config_val {expected['config_val']} for {expected['server_id']} at {expected['timestamp']}, found {match['config_val']}."
        assert match["ip_address"] == expected["ip_address"], f"Expected masked IP {expected['ip_address']} for {expected['server_id']} at {expected['timestamp']}, found {match['ip_address']}."


def test_sampled_configs_exists():
    assert os.path.exists(SAMPLED_FILE), f"The file {SAMPLED_FILE} does not exist."


def test_sampled_configs_content():
    assert os.path.exists(SAMPLED_FILE), f"The file {SAMPLED_FILE} does not exist."
    assert os.path.exists(PROCESSED_FILE), f"The file {PROCESSED_FILE} does not exist."

    with open(PROCESSED_FILE, "r", newline="") as f:
        full_rows = list(csv.DictReader(f))

    with open(SAMPLED_FILE, "r", newline="") as f:
        reader = csv.DictReader(f)
        sampled_rows = list(reader)

    assert reader.fieldnames == EXPECTED_COLUMNS, f"Expected columns {EXPECTED_COLUMNS} in {SAMPLED_FILE}, found {reader.fieldnames}."

    expected_sample_size = round(len(full_rows) * 0.25)
    assert abs(len(sampled_rows) - expected_sample_size) <= 2, f"Expected around {expected_sample_size} rows in {SAMPLED_FILE}, found {len(sampled_rows)}."

    for row in sampled_rows:
        assert row in full_rows, f"Row {row} in {SAMPLED_FILE} is not in {PROCESSED_FILE}."

    expected_full = get_expected_resampled_data()
    _, expected_sample = train_test_split(
        expected_full,
        test_size=0.25,
        random_state=42,
        stratify=[row["role"] for row in expected_full],
    )

    assert len(sampled_rows) == len(expected_sample), f"Expected exactly {len(expected_sample)} stratified rows, found {len(sampled_rows)}."
    assert Counter(map(row_key, sampled_rows)) == Counter(map(row_key, expected_sample)), \
        "The sample is not the reproducible 25% role-stratified sample produced with random seed 42."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
