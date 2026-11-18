#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_percentile_90_file_exists_and_correct():
    output_file = "/home/user/percentile_90.txt"

    assert os.path.isfile(output_file), f"The output file {output_file} does not exist."

    with open(output_file, "r") as f:
        content = f.read().strip()

    assert content != "", f"The output file {output_file} is empty."

    # The expected value based on the fixed seed in the setup script
    expected_value = "77402.73"

    assert content == expected_value, f"Expected the value in {output_file} to be {expected_value}, but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
