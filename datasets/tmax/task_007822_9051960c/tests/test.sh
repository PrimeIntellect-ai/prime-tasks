#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import unicodedata
import pytest

INPUT_FILE = "/home/user/app_logs.jsonl"
OUTPUT_FILE = "/home/user/processed_logs.jsonl"

def compute_expected_data():
    if not os.path.exists(INPUT_FILE):
        pytest.fail(f"Input file {INPUT_FILE} is missing, cannot compute expected state.")

    raw_logs = []
    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                raw_logs.append(json.loads(line))

    # Step 1 & 2: Normalize, strip, and prepare for deduplication
    for log in raw_logs:
        normalized_text = unicodedata.normalize("NFKC", log["feedback_text"]).strip()
        log["feedback_text"] = normalized_text
        log["_hash"] = hashlib.md5(normalized_text.encode("utf-8")).hexdigest()
        log["text_length"] = len(normalized_text)

    # Step 3: Sort by timestamp ascending
    raw_logs.sort(key=lambda x: x["timestamp"])

    # Step 2 (Deduplication): Keep first by timestamp
    seen_hashes = set()
    deduped_logs = []
    for log in raw_logs:
        if log["_hash"] not in seen_hashes:
            seen_hashes.add(log["_hash"])
            deduped_logs.append(log)

    # Step 4: Interpolation & Imputation
    # Find indices with non-null temperatures
    valid_temps = [(i, log["cpu_temperature"]) for i, log in enumerate(deduped_logs) if log["cpu_temperature"] is not None]

    if not valid_temps:
        # Edge case: no valid temps at all
        pass
    else:
        # Forward/Backward fill for edges, linear for middle
        for i, log in enumerate(deduped_logs):
            if log["cpu_temperature"] is None:
                # Find surrounding valid temps
                prev_valid = next(((idx, val) for idx, val in reversed(valid_temps) if idx < i), None)
                next_valid = next(((idx, val) for idx, val in valid_temps if idx > i), None)

                if prev_valid is None and next_valid is not None:
                    # Backward fill
                    log["cpu_temperature"] = next_valid[1]
                elif next_valid is None and prev_valid is not None:
                    # Forward fill
                    log["cpu_temperature"] = prev_valid[1]
                elif prev_valid is not None and next_valid is not None:
                    # Linear interpolation
                    idx_diff = next_valid[0] - prev_valid[0]
                    val_diff = next_valid[1] - prev_valid[1]
                    step = val_diff / idx_diff
                    interpolated_val = prev_valid[1] + step * (i - prev_valid[0])
                    log["cpu_temperature"] = interpolated_val

    # Round temperatures and clean up internal fields
    for log in deduped_logs:
        if log["cpu_temperature"] is not None:
            log["cpu_temperature"] = round(log["cpu_temperature"], 1)
        del log["_hash"]

    return deduped_logs

def test_processed_file_exists():
    assert os.path.exists(OUTPUT_FILE), f"The output file {OUTPUT_FILE} does not exist."
    assert os.path.isfile(OUTPUT_FILE), f"The path {OUTPUT_FILE} is not a file."

def test_processed_file_contents():
    expected_data = compute_expected_data()

    actual_data = []
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                actual_data.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {OUTPUT_FILE} is not valid JSON.")

    assert len(actual_data) == len(expected_data), (
        f"Expected {len(expected_data)} log entries after deduplication, "
        f"found {len(actual_data)}."
    )

    for i, (expected, actual) in enumerate(zip(expected_data, actual_data)):
        # Check required keys
        expected_keys = {"timestamp", "log_id", "feedback_text", "cpu_temperature", "text_length"}
        actual_keys = set(actual.keys())
        assert expected_keys.issubset(actual_keys), (
            f"Row {i} is missing required keys. Expected: {expected_keys}, Got: {actual_keys}"
        )

        # Check values
        assert actual["log_id"] == expected["log_id"], f"Row {i} log_id mismatch. Expected {expected['log_id']}, got {actual['log_id']}"
        assert actual["timestamp"] == expected["timestamp"], f"Row {i} timestamp mismatch for log {expected['log_id']}."
        assert actual["feedback_text"] == expected["feedback_text"], f"Row {i} feedback_text mismatch for log {expected['log_id']}."
        assert actual["text_length"] == expected["text_length"], f"Row {i} text_length mismatch for log {expected['log_id']}."

        # Temperature check with floating point tolerance
        expected_temp = expected["cpu_temperature"]
        actual_temp = actual["cpu_temperature"]
        assert type(expected_temp) == type(actual_temp), f"Row {i} cpu_temperature type mismatch."
        if expected_temp is not None:
            assert abs(expected_temp - actual_temp) <= 0.05, (
                f"Row {i} cpu_temperature mismatch. Expected {expected_temp}, got {actual_temp}"
            )

def test_sorting_by_timestamp():
    actual_data = []
    if not os.path.exists(OUTPUT_FILE):
        pytest.skip("Output file missing.")
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                actual_data.append(json.loads(line))

    timestamps = [log.get("timestamp", 0) for log in actual_data]
    assert timestamps == sorted(timestamps), "The output logs are not strictly sorted by timestamp in ascending order."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
