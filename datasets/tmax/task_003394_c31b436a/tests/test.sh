#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import hashlib
import glob
import pytest

def get_expected_records():
    raw_logs_dir = "/home/user/raw_logs"
    csv_files = glob.glob(os.path.join(raw_logs_dir, "*.csv"))

    records = []
    for file in csv_files:
        with open(file, "r", encoding="utf-8", errors="replace") as f:
            reader = csv.DictReader(f)
            for row in reader:
                msg = row["RawMessage"].lower()
                if "login" in msg:
                    action = "login"
                elif "logout" in msg:
                    action = "logout"
                elif "timeout" in msg:
                    action = "timeout"
                else:
                    action = "unknown"

                hash_input = f"{row['Timestamp']}|{row['User']}|{action}"
                row_hash = hashlib.md5(hash_input.encode('utf-8')).hexdigest()

                records.append({
                    "LogID": int(row["LogID"]),
                    "timestamp": row["Timestamp"],
                    "user": row["User"],
                    "action": action,
                    "hash": row_hash
                })

    records.sort(key=lambda x: (x["timestamp"], x["LogID"]))

    seen_hashes = set()
    final_records = []

    for r in records:
        if r["hash"] not in seen_hashes:
            seen_hashes.add(r["hash"])
            final_records.append({
                "hash": r["hash"],
                "timestamp": r["timestamp"],
                "user": r["user"],
                "action": r["action"]
            })

    return final_records

def test_processed_logs_exists():
    assert os.path.isfile("/home/user/processed_logs.jsonl"), "The output file /home/user/processed_logs.jsonl does not exist."

def test_processed_logs_content():
    expected_records = get_expected_records()

    output_file = "/home/user/processed_logs.jsonl"
    assert os.path.isfile(output_file), f"Output file missing: {output_file}"

    actual_records = []
    with open(output_file, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                actual_records.append(record)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {output_file} is not valid JSON.")

    assert len(actual_records) == len(expected_records), (
        f"Expected {len(expected_records)} records, but found {len(actual_records)}. "
        "Check deduplication and filtering logic."
    )

    for i, (actual, expected) in enumerate(zip(actual_records, expected_records)):
        assert isinstance(actual, dict), f"Record {i} is not a JSON object."

        expected_keys = {"hash", "timestamp", "user", "action"}
        assert set(actual.keys()) == expected_keys, (
            f"Record {i} has incorrect keys. Expected {expected_keys}, got {set(actual.keys())}."
        )

        assert actual["hash"] == expected["hash"], f"Record {i} hash mismatch. Expected {expected['hash']}, got {actual['hash']}."
        assert actual["timestamp"] == expected["timestamp"], f"Record {i} timestamp mismatch."
        assert actual["user"] == expected["user"], f"Record {i} user mismatch."
        assert actual["action"] == expected["action"], f"Record {i} action mismatch."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
