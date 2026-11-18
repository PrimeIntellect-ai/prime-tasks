#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_c_program_exists():
    """Test that the C program source file exists."""
    assert os.path.isfile('/home/user/process_drift.c'), "The C program /home/user/process_drift.c is missing."

def test_pipeline_script_exists_and_executable():
    """Test that the pipeline script exists and is executable."""
    script_path = '/home/user/pipeline.sh'
    assert os.path.isfile(script_path), f"The script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

def test_drift_report_exists():
    """Test that the drift report CSV file exists."""
    assert os.path.isfile('/home/user/drift_report.csv'), "The output file /home/user/drift_report.csv is missing."

def test_drift_report_contents():
    """Test that the drift report CSV file contains the correct computed values."""
    expected_data = [
        "0,40,110,160,17.32",
        "10,43,108,158,13.30",
        "20,49,101,151,1.73",
        "30,56,94,144,10.39",
        "40,62,88,138,20.78",
        "50,65,85,135,25.98",
        "60,69,81,131,32.91",
        "70,73,77,127,39.84",
        "80,76,74,124,45.03",
        "90,80,70,120,51.96",
        "100,80,70,120,51.96"
    ]

    with open('/home/user/drift_report.csv', 'r') as f:
        actual = [line.strip() for line in f if line.strip()]

    assert actual == expected_data, f"Output mismatch in /home/user/drift_report.csv.\nExpected:\n{expected_data}\nGot:\n{actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
