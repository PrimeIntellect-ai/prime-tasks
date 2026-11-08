#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
from collections import defaultdict

def test_clean_aggregated_exists():
    """Test that the output file exists."""
    output_file = "/home/user/clean_aggregated.csv"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."
    assert os.path.isfile(output_file), f"{output_file} should be a file."

def test_clean_aggregated_content():
    """Test that the output file contains the correctly aggregated, filtered, and sorted data."""
    input_file = "/home/user/raw_sensors.csv"
    output_file = "/home/user/clean_aggregated.csv"

    assert os.path.exists(input_file), f"Input file {input_file} is missing."
    assert os.path.exists(output_file), f"Output file {output_file} is missing."

    # Define time buckets mapping
    buckets = {
        3: '00-04', # v0
        4: '04-08', # v1
        5: '08-12', # v2
        6: '12-16', # v3
        7: '16-20', # v4
        8: '20-24'  # v5
    }

    # Compute expected data
    grouped_data = defaultdict(list)
    with open(input_file, "r") as f:
        lines = f.read().strip().split('\n')
        if not lines:
            return
        header = lines[0].split(',')
        for line in lines[1:]:
            parts = line.split(',')
            if len(parts) < 9:
                continue
            metric = parts[2]
            for col_idx, bucket_name in buckets.items():
                try:
                    val = float(parts[col_idx])
                    if val >= 0:
                        grouped_data[(metric, bucket_name)].append(val)
                except ValueError:
                    pass

    # Calculate averages and format
    results = []
    for (metric, bucket), values in grouped_data.items():
        if values:
            avg = sum(values) / len(values)
            results.append({
                'metric': metric,
                'bucket': bucket,
                'avg': avg
            })

    # Sort: metric ascending, avg descending
    # To sort descending by avg, we can negate the avg since they are positive floats
    results.sort(key=lambda x: (x['metric'], -x['avg']))

    expected_lines = []
    for r in results:
        expected_lines.append(f"{r['metric']},{r['bucket']},{r['avg']:.2f}")

    expected_output = "\n".join(expected_lines)

    with open(output_file, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_output, (
        "The content of the aggregated file does not match the expected output.\n"
        f"Expected:\n{expected_output}\n\nGot:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
