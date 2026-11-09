#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_cpp_files_exist():
    cpp_file = "/home/user/process_logs.cpp"
    executable = "/home/user/process_logs"

    assert os.path.exists(cpp_file), f"C++ source file {cpp_file} does not exist."
    assert os.path.isfile(cpp_file), f"{cpp_file} is not a file."

    assert os.path.exists(executable), f"Executable {executable} does not exist."
    assert os.path.isfile(executable), f"{executable} is not a file."
    assert os.access(executable, os.X_OK), f"{executable} is not executable."

def test_summary_csv_content():
    summary_file = "/home/user/data/summary.csv"

    assert os.path.exists(summary_file), f"Output file {summary_file} does not exist."
    assert os.path.isfile(summary_file), f"{summary_file} is not a file."

    expected_content = """NodeName,EventCode,TotalCount
NodeAlpha,E-404,10
NodeAlpha,E-500,2
NodeAlpha,I-100,5
NodeAlpha,W-001,15
NodeBeta,E-404,5
NodeBeta,E-500,20
NodeBeta,I-100,5
NodeBeta,W-001,15
NodeGamma,E-404,10
NodeGamma,E-500,5
NodeGamma,I-100,5
NodeGamma,W-001,15"""

    with open(summary_file, 'r') as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {summary_file} does not match the expected aggregated output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
