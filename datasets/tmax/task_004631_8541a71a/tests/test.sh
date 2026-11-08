#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_similar_items_file_exists():
    """Test that the similar_items.txt file has been created."""
    file_path = "/home/user/similar_items.txt"
    assert os.path.isfile(file_path), f"File not found: {file_path}. Did you write the output?"

def test_similar_items_content():
    """Test that the similar_items.txt file contains the correct top 3 items."""
    file_path = "/home/user/similar_items.txt"
    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_content = "102,106,104"
    assert content == expected_content, (
        f"Incorrect content in {file_path}. "
        f"Expected '{expected_content}', but got '{content}'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
