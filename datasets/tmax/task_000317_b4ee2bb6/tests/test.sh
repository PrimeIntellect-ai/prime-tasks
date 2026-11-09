#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def expected_lines_from_raw():
    buckets = {}
    with open('/home/user/raw_metrics.log', 'r') as f:
        for line in f:
            timestamp_s, metric_code_s, value_s = line.split()
            timestamp = int(timestamp_s)
            metric_code = int(metric_code_s)
            value = float(value_s)
            bucket = timestamp - (timestamp % 60)
            if bucket not in buckets:
                buckets[bucket] = {1: 0.0, 2: 0.0, 3: 0.0}
            if value > buckets[bucket][metric_code]:
                buckets[bucket][metric_code] = value

    return [
        f"{bucket},{buckets[bucket][1]:.2f},{buckets[bucket][2]:.2f},{buckets[bucket][3]:.2f}"
        for bucket in sorted(buckets)
    ]


def test_c_file_exists():
    c_path = '/home/user/process_logs.c'
    assert os.path.exists(c_path), f"Source file {c_path} is missing. Did you write the C program?"
    assert os.path.isfile(c_path), f"{c_path} is not a file."


def test_executable_exists():
    exe_path = '/home/user/process_logs'
    assert os.path.exists(exe_path), f"Executable {exe_path} is missing. Did you compile the C program?"
    assert os.path.isfile(exe_path), f"{exe_path} is not a file."
    assert os.access(exe_path, os.X_OK), f"{exe_path} is not executable."


def test_output_csv_exists():
    out_path = '/home/user/aggregated_metrics.csv'
    assert os.path.exists(out_path), f"Output file {out_path} is missing."
    assert os.path.isfile(out_path), f"{out_path} is not a file."


def test_output_csv_content():
    out_path = '/home/user/aggregated_metrics.csv'
    assert os.path.exists(out_path), f"Output file {out_path} is missing."

    with open(out_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    expected_lines = expected_lines_from_raw()

    assert len(actual_lines) == len(expected_lines), (
        f"Output file has {len(actual_lines)} lines, but expected {len(expected_lines)} lines."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} mismatch.\n"
            f"Expected: {expected}\n"
            f"Actual:   {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
