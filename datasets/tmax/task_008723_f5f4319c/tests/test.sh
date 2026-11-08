#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def compute_median(values):
    sorted_vals = sorted(values)
    n = len(sorted_vals)
    if n == 0:
        return 0.0
    if n % 2 == 1:
        return sorted_vals[n // 2]
    else:
        return (sorted_vals[n // 2 - 1] + sorted_vals[n // 2]) / 2.0

def test_final_group_projection():
    input_file = '/home/user/sensor_data.csv'
    output_file = '/home/user/group_projection.csv'

    assert os.path.exists(output_file), f"Output file {output_file} is missing."

    # Read input data
    data = []
    with open(input_file, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append(row)

    # Compute medians
    features = ['F1', 'F2', 'F3', 'F4', 'F5']
    medians = {}
    for feat in features:
        vals = [float(row[feat]) for row in data if row[feat].strip() != '']
        medians[feat] = compute_median(vals)

    # Process data and compute projections
    weights = [0.2, -0.5, 0.4, 0.7, -0.3]
    groups = {}
    for row in data:
        group_id = int(row['group_id'])
        proj = 0.0
        for i, feat in enumerate(features):
            val_str = row[feat].strip()
            if val_str == '':
                val = int(medians[feat])
            else:
                val = int(float(val_str))
            proj += val * weights[i]

        if group_id not in groups:
            groups[group_id] = []
        groups[group_id].append(proj)

    # Aggregate
    expected_results = {}
    for gid, projs in groups.items():
        mean_proj = sum(projs) / len(projs)
        expected_results[gid] = round(mean_proj, 4)

    # Read student output
    student_results = {}
    with open(output_file, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['group_id', 'mean_projection'], f"Expected header ['group_id', 'mean_projection'], got {header}"

        for row in reader:
            if not row:
                continue
            assert len(row) == 2, f"Expected 2 columns in output, got {len(row)} in row {row}"
            gid = int(row[0])
            mean_proj = float(row[1])
            student_results[gid] = mean_proj

    # Check results
    expected_sorted_gids = sorted(expected_results.keys())
    student_sorted_gids = sorted(student_results.keys())

    assert student_sorted_gids == expected_sorted_gids, f"Expected group_ids {expected_sorted_gids}, got {student_sorted_gids}"

    # Check ordering in file
    with open(output_file, 'r', newline='') as f:
        reader = csv.DictReader(f)
        file_gids = [int(row['group_id']) for row in reader if row]
    assert file_gids == expected_sorted_gids, "Output file is not sorted by group_id in ascending order."

    for gid in expected_sorted_gids:
        expected_val = expected_results[gid]
        student_val = student_results[gid]
        assert abs(expected_val - student_val) <= 1e-4, f"Group {gid}: Expected mean_projection {expected_val}, got {student_val}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
