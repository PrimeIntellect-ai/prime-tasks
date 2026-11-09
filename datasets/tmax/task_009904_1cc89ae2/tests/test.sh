#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_optimal_gc_prob_file():
    output_file = "/home/user/optimal_gc_prob.txt"

    assert os.path.exists(output_file), f"The output file {output_file} does not exist."
    assert os.path.isfile(output_file), f"The path {output_file} is not a file."

    with open(output_file, 'r') as f:
        content = f.read().strip()

    assert content != "", f"The file {output_file} is empty."

    try:
        val = float(content)
    except ValueError:
        raise AssertionError(f"The content of {output_file} is not a valid float: '{content}'")

    # Check if it has 4 decimal places
    parts = content.split('.')
    if len(parts) == 2:
        assert len(parts[1]) == 4, f"The value should be rounded to exactly 4 decimal places, got '{content}'"
    else:
        raise AssertionError(f"The value should have a decimal point and 4 decimal places, got '{content}'")

    # The expected value for the fixed seed provided in the setup is 0.4542
    expected_val = "0.4542"
    assert content == expected_val, f"Expected probability {expected_val}, but got {content}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
