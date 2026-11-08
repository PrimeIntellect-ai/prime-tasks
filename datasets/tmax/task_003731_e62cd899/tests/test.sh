#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def test_bootstrap_mean_file_exists():
    """Check if the output file bootstrap_mean.txt exists."""
    file_path = '/home/user/bootstrap_mean.txt'
    assert os.path.isfile(file_path), f"Output file {file_path} is missing. Ensure you saved your result."


def test_bootstrap_mean_value():
    """Check if the calculated bootstrap mean matches the expected truth."""
    output_file = '/home/user/bootstrap_mean.txt'
    truth_file = '/tests/.expected_truth'

    assert os.path.isfile(truth_file), f"Truth file {truth_file} is missing. Test setup might have failed."
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    with open(output_file, 'r') as f:
        user_output = f.read().strip()

    with open(truth_file, 'r') as f:
        expected_output = f.read().strip()

    assert user_output == expected_output, (
        f"The calculated mean in {output_file} ({user_output}) "
        f"does not match the expected value ({expected_output}). "
        "Check your filtering logic, random seed, and rounding."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
