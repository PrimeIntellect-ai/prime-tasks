#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

def test_run_pipeline_executable():
    """Test that run_pipeline.sh exists and is executable."""
    script_path = '/home/user/run_pipeline.sh'
    assert os.path.isfile(script_path), f"Script not found: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"

def test_run_pipeline_execution_and_output():
    """Test running the pipeline and verifying the output."""
    script_path = '/home/user/run_pipeline.sh'
    output_path = '/home/user/output.txt'
    expected_output_path = '/tests/.expected_output'

    # Ensure expected output file exists
    assert os.path.isfile(expected_output_path), f"Expected output file missing: {expected_output_path}"

    # Run the script
    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with return code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    # Check if output file was created
    assert os.path.isfile(output_path), f"Output file was not created: {output_path}"

    # Read output and expected output
    with open(output_path, 'r') as f:
        output_content = f.read().strip()

    with open(expected_output_path, 'r') as f:
        expected_content = f.read().strip()

    # Compare outputs
    assert output_content == expected_content, f"Output content mismatch. Expected '{expected_content}', but got '{output_content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
