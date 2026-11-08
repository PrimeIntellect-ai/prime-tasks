#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess

def test_test_runner_exists_and_runs():
    script_path = "/home/user/test_runner.py"
    assert os.path.exists(script_path), f"Script not found at {script_path}"

    # Run the script to generate the results.json file
    result = subprocess.run(["python3", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to run. Stderr: {result.stderr}\nStdout: {result.stdout}"

def test_results_json_correct():
    results_path = "/home/user/results.json"
    expected_path = "/tests/expected_results.json"

    assert os.path.exists(results_path), f"Output file not found at {results_path}"
    assert os.path.exists(expected_path), f"Expected results file not found at {expected_path}"

    with open(results_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{results_path} is not valid JSON"

    with open(expected_path, "r") as f:
        expected = json.load(f)

    assert results == expected, f"Results do not match expected.\nGot: {results}\nExpected: {expected}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
