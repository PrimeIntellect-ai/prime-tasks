#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import struct
import pytest

WORKSPACE_DIR = "/home/user/workspace"
METRICS_LOG = os.path.join(WORKSPACE_DIR, "metrics.log")
DATA_BIN = os.path.join(WORKSPACE_DIR, "data.bin")

def compute_expected():
    """
    Recompute the expected count and average directly from the binary data file
    to ensure the logic matches the task intent exactly.
    """
    with open(DATA_BIN, "rb") as f:
        data = f.read()

    offset = 0
    count = 0
    total_sum = 0.0

    # 8 bytes per record: 1 byte magic, 2 bytes ID, 4 bytes float, 1 byte padding
    while offset + 8 <= len(data):
        if data[offset] != 0xAA:
            offset += 1
            continue

        # Unpack the 4-byte float (little-endian)
        _, _, val, _ = struct.unpack('<BHfB', data[offset:offset+8])
        count += 1
        total_sum += val
        offset += 8

    return count, total_sum

def test_metrics_log_exists():
    assert os.path.isfile(METRICS_LOG), f"Metrics log not found at {METRICS_LOG}. Did you run the application and save its output?"

def test_metrics_log_content():
    expected_count, expected_sum = compute_expected()
    expected_avg = expected_sum / expected_count if expected_count else 0.0

    with open(METRICS_LOG, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in metrics.log, got {len(lines)}. Content: {lines}"

    count_line = lines[0]
    avg_line = lines[1]

    assert count_line.startswith("Total Count: "), f"First line must start with 'Total Count: ', got '{count_line}'"
    assert avg_line.startswith("Average Value: "), f"Second line must start with 'Average Value: ', got '{avg_line}'"

    actual_count_str = count_line.split(":", 1)[1].strip()
    actual_avg_str = avg_line.split(":", 1)[1].strip()

    assert actual_count_str == str(expected_count), f"Expected count {expected_count}, got {actual_count_str}. Check your corruption recovery and race condition fixes."

    expected_avg_str = f"{expected_avg:.4f}"
    assert actual_avg_str == expected_avg_str, f"Expected average {expected_avg_str}, got {actual_avg_str}. Check your precision loss fix (double) and race condition fixes."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
