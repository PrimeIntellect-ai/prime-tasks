#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_page2_results():
    results_path = "/home/user/page2_results.txt"

    assert os.path.exists(results_path), f"File {results_path} does not exist."
    assert os.path.isfile(results_path), f"{results_path} is not a file."

    with open(results_path, "r") as f:
        content = f.read().strip().splitlines()

    expected_content = ["N8", "N1", "N6"]

    assert content == expected_content, f"Expected {expected_content} in {results_path}, got {content}."

def test_neuro_index():
    index_path = "/home/user/neuro_index.txt"

    assert os.path.exists(index_path), f"File {index_path} does not exist."
    assert os.path.isfile(index_path), f"{index_path} is not a file."

    with open(index_path, "r") as f:
        content = f.read().strip().splitlines()

    expected_content = [
        "N1:1",
        "N2:3",
        "N3:4",
        "N4:5",
        "N5:6",
        "N6:7",
        "N7:8",
        "N8:9"
    ]

    assert content == expected_content, f"Expected {expected_content} in {index_path}, got {content}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
