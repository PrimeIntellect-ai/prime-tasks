#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import struct
import statistics
import pytest

def get_expected_report():
    data_path = "/home/user/corrupted_metrics.dat"
    assert os.path.exists(data_path), f"Input file {data_path} missing."

    with open(data_path, "rb") as f:
        data = f.read()

    idx = 0
    struct_fmt = "<I d f"
    record_size = struct.calcsize(struct_fmt)
    records = []

    while idx < len(data):
        if idx + 4 <= len(data) and struct.unpack("<I", data[idx:idx+4])[0] == 0xDEADBEEF:
            idx += 8
            continue

        if idx + record_size <= len(data):
            records.append(struct.unpack(struct_fmt, data[idx:idx+record_size]))
            idx += record_size
        else:
            break

    latencies = [r[2] for r in records]
    mean = statistics.mean(latencies)
    stddev = statistics.stdev(latencies)
    threshold = mean + 3 * stddev

    anomalies = [r for r in records if r[2] > threshold]
    target_id = max(anomalies, key=lambda x: x[2])[0]

    return (
        f"Format: {struct_fmt}\n"
        f"Mean: {mean:.2f}\n"
        f"StdDev: {stddev:.2f}\n"
        f"TargetID: {target_id}\n"
    )

def test_anomaly_report_exists_and_correct():
    """Verify that the anomaly report exists and contains the correct derived values."""
    report_path = "/home/user/anomaly_report.txt"
    assert os.path.exists(report_path), f"File {report_path} is missing. Task incomplete."
    assert os.path.isfile(report_path), f"{report_path} is not a file."

    with open(report_path, "r") as f:
        actual_content = f.read().strip()

    expected_content = get_expected_report().strip()

    assert actual_content == expected_content, (
        f"Content of {report_path} is incorrect.\n"
        f"Expected:\n{expected_content}\n\n"
        f"Actual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
