#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_diagnostic_result_exists_and_correct():
    result_path = '/home/user/diagnostic_result.txt'

    # Check if the result file was created
    assert os.path.isfile(result_path), f"The result file {result_path} is missing. Did you save the output?"

    # Read the contents and verify the output
    with open(result_path, 'r') as f:
        content = f.read().strip()

    expected_result = "3.85"
    assert content == expected_result, f"Expected the result file to contain exactly '{expected_result}', but found '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
