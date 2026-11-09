#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_csv_exists():
    path = "/home/user/experiment_tracking.csv"
    assert os.path.isfile(path), f"Expected output file {path} does not exist. The program must generate this file."

def test_csv_content():
    path = "/home/user/experiment_tracking.csv"
    assert os.path.isfile(path), f"Expected output file {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "Node,Mean,CI_Lower,CI_Upper",
        "node_alpha,10.000,8.954,11.046",
        "node_beta,25.000,23.904,26.096",
        "node_gamma,5.000,4.690,5.310"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in the CSV, but got {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch in CSV.\nExpected: {expected}\nGot:      {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
