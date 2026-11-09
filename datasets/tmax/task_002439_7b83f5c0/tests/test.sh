#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import pytest

def test_recover_passwords_accuracy():
    go_file = "/home/user/recover_passwords.go"
    assert os.path.isfile(go_file), f"Missing Go file at {go_file}"

    # Compile the Go program
    compile_cmd = ["go", "build", "-o", "/tmp/recover_passwords", go_file]
    result = subprocess.run(compile_cmd, capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to compile Go program:\n{result.stderr}"

    # Run the compiled program against the hidden test set
    test_logs = "/app/hidden_test_logs.log"
    test_wordlist = "/app/hidden_wordlist.txt"
    output_json = "/tmp/results.json"
    expected_json = "/tests/expected_results.json"

    # Ensure previous output doesn't exist
    if os.path.exists(output_json):
        os.remove(output_json)

    run_cmd = ["/tmp/recover_passwords", test_logs, test_wordlist, output_json]
    result = subprocess.run(run_cmd, capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to run Go program:\n{result.stderr}\n{result.stdout}"

    assert os.path.isfile(output_json), f"Output JSON not found at {output_json}. Program did not create the output file."

    # Load actual and expected results
    with open(output_json, "r") as f:
        try:
            actual_results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file at {output_json} is not valid JSON")

    with open(expected_json, "r") as f:
        expected_results = json.load(f)

    total_accounts = len(expected_results)
    assert total_accounts > 0, "Expected results file is empty, test setup is broken."

    # Calculate accuracy
    correct = 0
    for username, expected_password in expected_results.items():
        if actual_results.get(username) == expected_password:
            correct += 1

    accuracy = correct / total_accounts
    assert accuracy >= 0.99, (
        f"Password recovery accuracy too low. "
        f"Metric: {accuracy:.4f}, Threshold: 0.99. "
        f"({correct} correct out of {total_accounts} accounts)"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
