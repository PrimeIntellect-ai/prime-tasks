#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_result_file_exists_and_correct():
    result_file = "/home/user/result_integral.txt"

    # Check if file exists
    assert os.path.isfile(result_file), f"Expected result file {result_file} does not exist."

    # Read the content
    with open(result_file, 'r') as f:
        content = f.read().strip()

    assert content, f"File {result_file} is empty."

    # Parse the value
    try:
        val = float(content)
    except ValueError:
        assert False, f"Content of {result_file} is not a valid float: '{content}'"

    # The expected value is approximately 10738.71
    # We allow a tolerance of +/- 2.0 to account for minor differences in solver tolerances/methods
    expected = 10738.71
    tolerance = 2.0

    assert abs(val - expected) <= tolerance, (
        f"Calculated integral value {val} is outside the acceptable range "
        f"[{expected - tolerance}, {expected + tolerance}]."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
