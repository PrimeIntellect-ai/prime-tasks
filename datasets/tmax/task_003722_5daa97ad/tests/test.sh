#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import difflib
import pytest

def test_reconstructed_ticker_similarity():
    expected_path = "/tests/ground_truth.txt"
    actual_path = "/home/user/reconstructed_ticker.txt"

    assert os.path.exists(expected_path), f"Ground truth file missing: {expected_path}"
    assert os.path.exists(actual_path), f"Agent output file missing: {actual_path}"

    with open(expected_path, "r", encoding="utf-8") as f:
        expected_text = f.read().strip()

    with open(actual_path, "r", encoding="utf-8") as f:
        actual_text = f.read().strip()

    assert len(actual_text) > 0, "Agent output file is empty."

    score = difflib.SequenceMatcher(None, expected_text, actual_text).ratio()

    threshold = 0.85
    assert score >= threshold, (
        f"SequenceMatcher ratio {score:.4f} is less than the required threshold {threshold}. "
        f"Expected text: '{expected_text}'. Actual text: '{actual_text}'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
