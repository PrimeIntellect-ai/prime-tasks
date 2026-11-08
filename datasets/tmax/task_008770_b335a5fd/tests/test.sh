#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import pytest

def read_and_smooth(filepath):
    """
    Reads a trajectory CSV, sorts by timestamp, and applies a rolling mean 
    (window=3, min_periods=1) to x and y coordinates.
    """
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        data = []
        for row in reader:
            data.append({
                'timestamp': float(row['timestamp']),
                'x': float(row['x']),
                'y': float(row['y'])
            })

    # Sort by timestamp ascending
    data.sort(key=lambda d: d['timestamp'])

    smoothed = []
    for i in range(len(data)):
        start = max(0, i - 2)
        window = data[start:i+1]
        mean_x = sum(d['x'] for d in window) / len(window)
        mean_y = sum(d['y'] for d in window) / len(window)
        smoothed.append((mean_x, mean_y))

    return smoothed

def test_summary_report_content():
    """
    Computes the expected ground truth using standard library functions
    and verifies that the generated summary report matches perfectly.
    """
    report_path = '/home/user/summary_report.txt'
    assert os.path.exists(report_path), f"The final report file {report_path} was not created."

    # 1. Compute smoothed baseline trajectory
    v1_smoothed = read_and_smooth('/home/user/trajectories/vehicle_1.csv')

    best_dist = float('inf')
    best_v = ""

    # 2. Compute similarity for vehicles 2 to 5
    for i in range(2, 6):
        v_name = f"vehicle_{i}.csv"
        v_smoothed = read_and_smooth(f'/home/user/trajectories/{v_name}')

        total_dist = 0.0
        for (x1, y1), (x2, y2) in zip(v1_smoothed, v_smoothed):
            total_dist += math.sqrt((x1 - x2)**2 + (y1 - y2)**2)

        avg_dist = total_dist / len(v1_smoothed)

        if avg_dist < best_dist:
            best_dist = avg_dist
            best_v = v_name

    expected_distance_str = f"{best_dist:.4f}"

    # 3. Read template and generate expected report
    template_path = '/home/user/template.txt'
    assert os.path.exists(template_path), f"Template file {template_path} is missing."

    with open(template_path, 'r') as f:
        template = f.read()

    expected_content = template.replace('{{VEHICLE_NAME}}', best_v).replace('{{DISTANCE}}', expected_distance_str)

    # 4. Compare with actual report
    with open(report_path, 'r') as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), (
        f"The content of {report_path} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n\n"
        f"Actual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
