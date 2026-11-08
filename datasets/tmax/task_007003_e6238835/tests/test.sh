#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_report_content():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    with open(report_path, "r") as f:
        content = f.read().strip().splitlines()

    expected = [
        "P002: 3",
        "P004: 2"
    ]

    assert content == expected, f"Report content is incorrect. Expected {expected}, got {content}"

def test_corrected_p002():
    p002_path = "/home/user/dataset/corrected/P002.gcode"
    assert os.path.isfile(p002_path), f"Corrected file {p002_path} is missing."

    with open(p002_path, "r") as f:
        content = f.read().strip().splitlines()

    expected = [
        "T0",
        "G1 X0 Y0 Z1.5",
        "G1 X10 Y0",
        "G1 X10 Y10 Z2.0",
        "T1",
        "G1 X20 Y20 Z2.0",
        "T0",
        "G1 X0 Y0 Z3.0"
    ]

    assert content == expected, f"P002.gcode content is incorrect. Expected {expected}, got {content}"

def test_corrected_p004():
    p004_path = "/home/user/dataset/corrected/P004.gcode"
    assert os.path.isfile(p004_path), f"Corrected file {p004_path} is missing."

    with open(p004_path, "r") as f:
        content = f.read().strip().splitlines()

    expected = [
        "T1",
        "G1 X1 Y1 Z0.1",
        "T0",
        "G1 X2 Y2 Z0.7",
        "G1 X3 Y3",
        "G1 X4 Y4 Z0.9"
    ]

    assert content == expected, f"P004.gcode content is incorrect. Expected {expected}, got {content}"

def test_no_extra_corrected_files():
    corrected_dir = "/home/user/dataset/corrected/"
    assert os.path.isdir(corrected_dir), f"Directory {corrected_dir} is missing."

    files = set(os.listdir(corrected_dir))
    expected_files = {"P002.gcode", "P004.gcode"}

    extra_files = files - expected_files
    assert not extra_files, f"Unexpected files found in {corrected_dir}: {extra_files}. Only failed prints should be corrected."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
