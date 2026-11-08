#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
from collections import defaultdict

def test_hourly_config_stats_exists():
    file_path = "/home/user/hourly_config_stats.csv"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

def test_hourly_config_stats_content():
    input_path = "/home/user/raw_configs.csv"
    output_path = "/home/user/hourly_config_stats.csv"

    assert os.path.isfile(input_path), f"Input file {input_path} is missing."

    # Process the input file
    stats = defaultdict(list)

    with open(input_path, "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)

        for row in reader:
            if len(row) != 5:
                continue

            timestamp, server_id, cpu, mem, conn = row

            # Validation: strict positive integers
            if not (cpu.isdigit() and mem.isdigit() and conn.isdigit()):
                continue

            cpu_val, mem_val, conn_val = int(cpu), int(mem), int(conn)
            if cpu_val <= 0 or mem_val <= 0 or conn_val <= 0:
                continue

            # Time-Based Bucketing (truncate to hour, e.g., 2023-11-01T08)
            hour = timestamp[:13]

            # Wide-to-Long Reshaping
            stats[(hour, server_id, "CPU")].append(cpu_val)
            stats[(hour, server_id, "MEM")].append(mem_val)
            stats[(hour, server_id, "CONN")].append(conn_val)

    # Mathematical Aggregation
    expected_lines = []
    for key, values in stats.items():
        hour, server_id, metric = key
        avg = sum(values) / len(values)
        expected_lines.append(f"{hour},{server_id},{metric},{avg:.2f}")

    # Formatting and Sorting
    expected_lines.sort()

    # Read the actual output
    with open(output_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Content of {output_path} does not match expected output.\n"
        f"Expected {len(expected_lines)} rows, got {len(actual_lines)}.\n"
        f"First mismatch or difference can be found by comparing expected vs actual."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
