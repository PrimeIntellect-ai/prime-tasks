#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def compute_expected():
    """Dynamically compute the expected output from the input trace file."""
    file_path = "/home/user/perf_trace.csv"
    if not os.path.exists(file_path):
        return None

    out_degrees = {}
    exec_times = {}

    with open(file_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            caller = row["caller_id"]
            callee = row["callee_id"]
            val = float(row["exec_time_ns"])

            if caller not in out_degrees:
                out_degrees[caller] = set()
                exec_times[caller] = []

            out_degrees[caller].add(callee)
            exec_times[caller].append(val)

    if not out_degrees:
        return None

    # Find max out-degree caller
    max_caller = None
    max_degree = -1
    for caller, callees in out_degrees.items():
        if len(callees) > max_degree:
            max_degree = len(callees)
            max_caller = caller

    # Calculate population variance for max_caller
    times = exec_times[max_caller]
    n = len(times)
    mean = sum(times) / n
    variance = sum((x - mean) ** 2 for x in times) / n

    return f"{max_caller},{max_degree},{variance:.4f}"

def test_bottleneck_analysis_result():
    """Verify that the bottleneck analysis output matches the expected result."""
    expected = compute_expected()
    assert expected is not None, "Could not compute expected result because perf_trace.csv is missing or empty."

    output_path = "/home/user/bottleneck_analysis.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    with open(output_path, "r") as f:
        content = f.read().strip()

    assert content == expected, f"File {output_path} content is incorrect. Expected '{expected}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
