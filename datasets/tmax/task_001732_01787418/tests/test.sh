#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_anomalies_output():
    log_path = '/home/user/sys_config.log'
    out_path = '/home/user/anomalies.txt'

    assert os.path.isfile(log_path), f"Input file {log_path} is missing."
    assert os.path.isfile(out_path), f"Output file {out_path} is missing."

    # Parse the log file to compute expected results
    max_mem_data = {}
    with open(log_path, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 3 and parts[1] == 'MAX_MEM':
                day = int(parts[0])
                val = int(parts[2])
                max_mem_data[day] = val

    if not max_mem_data:
        pytest.fail("No MAX_MEM data found in log.")

    min_day = min(max_mem_data.keys())
    max_day = max(max_mem_data.keys())

    # Forward fill
    filled_data = {}
    last_val = None
    for day in range(min_day, max_day + 1):
        if day in max_mem_data:
            last_val = max_mem_data[day]
        filled_data[day] = last_val

    # Compute rolling stats and distances
    expected_lines = []
    for day in range(min_day + 2, max_day + 1):
        v1 = filled_data[day - 2]
        v2 = filled_data[day - 1]
        v3 = filled_data[day]
        avg = (v1 + v2 + v3) / 3.0
        distance = abs(v3 - avg)
        expected_lines.append(f"{day} {distance:.2f}")

    expected_output = "\n".join(expected_lines)

    # Read actual output
    with open(out_path, 'r') as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, (
        f"Contents of {out_path} do not match expected results.\n"
        f"Expected:\n{expected_output}\n\nActual:\n{actual_output}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
