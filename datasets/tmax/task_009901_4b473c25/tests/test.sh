#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re

def test_result_file_exists_and_correct():
    """Test that the result.txt file exists and contains the correct output."""
    result_path = "/home/user/result.txt"
    assert os.path.exists(result_path), f"The file {result_path} does not exist. Did you save your output?"
    assert os.path.isfile(result_path), f"The path {result_path} is not a file."

    with open(result_path, "r") as f:
        content = f.read().strip()

    # Expected format: Index: X, Concentration: Y
    match = re.match(r"^Index:\s*(\d+),\s*Concentration:\s*([0-9\.]+)$", content)
    assert match is not None, (
        f"The file format is incorrect. Expected 'Index: X, Concentration: Y', "
        f"but got: '{content}'"
    )

    index = int(match.group(1))
    concentration = float(match.group(2))

    assert index == 2, f"Expected the optimal index to be 2, but got {index}."

    expected_concentration = 0.177093
    assert abs(concentration - expected_concentration) < 1e-5, (
        f"Expected the concentration to be approximately {expected_concentration}, "
        f"but got {concentration}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
