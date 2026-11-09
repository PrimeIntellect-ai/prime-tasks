#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_highest_outdegree_file():
    file_path = "/home/user/highest_outdegree.txt"
    assert os.path.isfile(file_path), f"The file {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected = "prod-users"
    assert content == expected, f"Expected '{expected}' in {file_path}, but got '{content}'."

def test_backup_chains_file():
    file_path = "/home/user/backup_chains.txt"
    assert os.path.isfile(file_path), f"The file {file_path} is missing."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "prod-inventory,prod-shipping,prod-analytics",
        "prod-orders,prod-shipping,prod-analytics",
        "prod-users,prod-inventory,prod-shipping",
        "prod-users,prod-logs,prod-metrics",
        "prod-users,prod-orders,prod-shipping"
    ]

    assert lines == expected_lines, f"The content of {file_path} does not match the expected backup chains. Got: {lines}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
