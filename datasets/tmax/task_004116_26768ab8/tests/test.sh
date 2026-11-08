#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

RAW_CSV_PATH = "/home/user/raw_metrics.csv"
CLEAN_CSV_PATH = "/home/user/clean_metrics.csv"
PIPELINE_LOG_PATH = "/home/user/pipeline.log"

def test_clean_metrics_content():
    assert os.path.isfile(RAW_CSV_PATH), f"Original raw CSV {RAW_CSV_PATH} is missing."
    assert os.path.isfile(CLEAN_CSV_PATH), f"Cleaned CSV {CLEAN_CSV_PATH} was not found."

    with open(RAW_CSV_PATH, "r") as f:
        raw_lines = [line.strip() for line in f if line.strip()]

    assert len(raw_lines) > 0, "Raw CSV is empty."

    # Compute expected clean CSV content
    expected_clean_lines = ["date,hour,user_id,masked_ip,cpu_usage,usage_category"]

    for row in raw_lines[1:]:
        cols = row.split(",")
        if len(cols) != 4:
            continue
        timestamp, user_id, ip_address, cpu_usage = cols

        # 1. Date and Hour
        # format: YYYY-MM-DDTHH:MM:SSZ
        date = timestamp[:10]
        hour = timestamp[11:13]

        # 2. Mask IP
        ip_parts = ip_address.split(".")
        masked_ip = ".".join(ip_parts[:-1]) + ".XXX"

        # 3. Usage Category
        try:
            cpu_val = float(cpu_usage)
        except ValueError:
            cpu_val = 0.0

        usage_category = "HIGH" if cpu_val >= 80.0 else "NORMAL"

        expected_clean_lines.append(f"{date},{hour},{user_id},{masked_ip},{cpu_usage},{usage_category}")

    with open(CLEAN_CSV_PATH, "r") as f:
        actual_clean_lines = [line.strip() for line in f if line.strip()]

    assert actual_clean_lines[0] == expected_clean_lines[0], f"Header in clean CSV is incorrect. Expected: {expected_clean_lines[0]}"

    assert len(actual_clean_lines) == len(expected_clean_lines), "Number of lines in clean CSV does not match expected."

    for i, (actual, expected) in enumerate(zip(actual_clean_lines, expected_clean_lines)):
        assert actual == expected, f"Row {i} mismatch. Expected: {expected}, Got: {actual}"

def test_pipeline_log():
    assert os.path.isfile(RAW_CSV_PATH), f"Original raw CSV {RAW_CSV_PATH} is missing."
    assert os.path.isfile(PIPELINE_LOG_PATH), f"Pipeline log {PIPELINE_LOG_PATH} was not found."

    with open(RAW_CSV_PATH, "r") as f:
        raw_lines = [line.strip() for line in f if line.strip()]

    num_data_rows = max(0, len(raw_lines) - 1)
    expected_log_content = f"Processed {num_data_rows} rows."

    with open(PIPELINE_LOG_PATH, "r") as f:
        actual_log_content = f.read().strip()

    assert actual_log_content == expected_log_content, f"Pipeline log content mismatch. Expected: '{expected_log_content}', Got: '{actual_log_content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
