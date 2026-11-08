#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess

def test_generate_report_exists():
    script_path = "/home/user/generate_report.go"
    assert os.path.isfile(script_path), f"The Go script is missing: {script_path}"

def test_execution_and_output():
    # Execute the script to generate/overwrite the output.json
    result = subprocess.run(
        ["go", "run", "generate_report.go"],
        cwd="/home/user",
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Execution of generate_report.go failed.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    output_path = "/home/user/output.json"
    assert os.path.isfile(output_path), f"Output JSON file was not created at {output_path}"

    with open(output_path, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{output_path} does not contain valid JSON"

    expected_data = [
        {"emp_id": 1, "name": "Alice (CEO)", "team_sales": 800, "peer_rank": 1},
        {"emp_id": 2, "name": "Bob (VP)", "team_sales": 300, "peer_rank": 2},
        {"emp_id": 3, "name": "Charlie (VP)", "team_sales": 500, "peer_rank": 1},
        {"emp_id": 4, "name": "Dave (Dev)", "team_sales": 50, "peer_rank": 2},
        {"emp_id": 5, "name": "Eve (Dev)", "team_sales": 150, "peer_rank": 1},
        {"emp_id": 6, "name": "Frank (Dev)", "team_sales": 300, "peer_rank": 1}
    ]

    assert actual_data == expected_data, (
        f"The generated JSON does not match the expected logic and schema.\n"
        f"Expected: {expected_data}\n"
        f"Actual: {actual_data}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
