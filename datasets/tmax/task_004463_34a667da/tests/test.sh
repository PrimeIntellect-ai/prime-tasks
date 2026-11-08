#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

FEATURES_FILE = "/home/user/training_mesh_features.txt"
VIS_FILE = "/home/user/mesh_vis.txt"
RAW_DATA_DIR = "/home/user/raw_mesh_data"

def compute_expected_results():
    quadrants = {
        "Q0_0": [],
        "Q1_0": [],
        "Q0_1": [],
        "Q1_1": []
    }

    for x in range(10):
        for y in range(10):
            filepath = os.path.join(RAW_DATA_DIR, f"sensor_{x}_{y}.csv")
            if not os.path.isfile(filepath):
                continue

            max_intensity = -float('inf')
            with open(filepath, 'r') as f:
                header = f.readline()
                for line in f:
                    if not line.strip():
                        continue
                    freq_str, int_str = line.strip().split(',')
                    freq = float(freq_str)
                    intensity = float(int_str)
                    if 1000 <= freq <= 1500:
                        if intensity > max_intensity:
                            max_intensity = intensity

            if x < 5 and y < 5:
                quadrants["Q0_0"].append(max_intensity)
            elif x >= 5 and y < 5:
                quadrants["Q1_0"].append(max_intensity)
            elif x < 5 and y >= 5:
                quadrants["Q0_1"].append(max_intensity)
            elif x >= 5 and y >= 5:
                quadrants["Q1_1"].append(max_intensity)

    averages = {}
    for q, values in quadrants.items():
        if values:
            averages[q] = sum(values) / len(values)
        else:
            averages[q] = 0.0

    return averages

def test_training_mesh_features_content():
    assert os.path.isfile(FEATURES_FILE), f"Output file {FEATURES_FILE} does not exist."

    expected_averages = compute_expected_results()
    expected_lines = [
        f"Q0_0: {expected_averages['Q0_0']:.2f}",
        f"Q1_0: {expected_averages['Q1_0']:.2f}",
        f"Q0_1: {expected_averages['Q0_1']:.2f}",
        f"Q1_1: {expected_averages['Q1_1']:.2f}"
    ]

    with open(FEATURES_FILE, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {FEATURES_FILE} are incorrect.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )

def test_mesh_vis_content():
    assert os.path.isfile(VIS_FILE), f"Output file {VIS_FILE} does not exist."

    expected_averages = compute_expected_results()
    expected_lines = [
        f"Q0_0: {'*' * int(expected_averages['Q0_0'] / 5)}",
        f"Q1_0: {'*' * int(expected_averages['Q1_0'] / 5)}",
        f"Q0_1: {'*' * int(expected_averages['Q0_1'] / 5)}",
        f"Q1_1: {'*' * int(expected_averages['Q1_1'] / 5)}"
    ]

    with open(VIS_FILE, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {VIS_FILE} are incorrect.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
