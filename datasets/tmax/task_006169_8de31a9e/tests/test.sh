#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

def test_c_program_exists():
    c_file = "/home/user/find_correlation.c"
    assert os.path.isfile(c_file), f"C program {c_file} is missing."

    with open(c_file, 'r') as f:
        content = f.read()

    assert "#include" in content, f"File {c_file} does not look like a valid C program."

def test_pipeline_script_exists_and_executable():
    script_file = "/home/user/pipeline.sh"
    assert os.path.isfile(script_file), f"Bash script {script_file} is missing."
    assert os.access(script_file, os.X_OK), f"Bash script {script_file} is not executable."

def test_pipeline_execution_and_output():
    script_file = "/home/user/pipeline.sh"
    output_file = "/home/user/highest_correlation.txt"

    # Remove output file if it exists to ensure the script creates it
    if os.path.exists(output_file):
        os.remove(output_file)

    # Run the pipeline script
    result = subprocess.run([script_file], cwd="/home/user", capture_output=True, text=True)
    assert result.returncode == 0, f"Pipeline script failed with return code {result.returncode}.\nStderr: {result.stderr}"

    # Check the output file
    assert os.path.isfile(output_file), f"Output file {output_file} was not created by the pipeline script."

    with open(output_file, 'r') as f:
        content = f.read().strip()

    expected_output = "2,4,-0.9765"
    assert content == expected_output, f"Expected output '{expected_output}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
