#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_best_match_file_exists():
    file_path = "/home/user/best_match.txt"
    assert os.path.isfile(file_path), f"Expected file {file_path} is missing. Did you create it?"

def test_best_match_content():
    file_path = "/home/user/best_match.txt"
    assert os.path.isfile(file_path), "Cannot check content because file is missing."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content, "The file /home/user/best_match.txt is empty."

    parts = content.split(",")
    assert len(parts) == 2, f"Expected format 'item_id,score', but got: {content}"

    item_id, score_str = parts[0].strip(), parts[1].strip()

    assert item_id == "D", f"Expected best match item_id to be 'D', but got '{item_id}'."

    try:
        score = float(score_str)
    except ValueError:
        pytest.fail(f"Expected score to be a valid float, but got '{score_str}'.")

    assert score == 9.0, f"Expected best match score to be 9.0, but got {score}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
