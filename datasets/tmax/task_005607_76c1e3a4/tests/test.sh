#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_recommendation_file_exists():
    """Check that the recommendation.txt file exists."""
    file_path = "/home/user/recommendation.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

def test_recommendation_content():
    """Check that the recommendation.txt file contains the correct mean accuracy."""
    file_path = "/home/user/recommendation.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_content = "Mean Accuracy: 0.865"
    assert content == expected_content, f"Expected content '{expected_content}', but found '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
