#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re

def test_best_experiment_file_exists():
    """Test that the best_experiment.txt file exists."""
    assert os.path.isfile("/home/user/best_experiment.txt"), "/home/user/best_experiment.txt is missing. The task requires writing the final answer to this file."

def test_best_experiment_content():
    """Test that the best_experiment.txt file has the correct content."""
    file_path = "/home/user/best_experiment.txt"
    assert os.path.isfile(file_path), f"{file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_pattern = r"^exp_alpha\.csv:\s*0\.6750$"
    assert re.match(expected_pattern, content), f"Content of {file_path} is incorrect. Expected 'exp_alpha.csv: 0.6750', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
