#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_final_w_exists():
    assert os.path.exists('/home/user/ml_data/final_W.txt'), "The file /home/user/ml_data/final_W.txt does not exist."

def test_final_w_format_and_values():
    agent_file = '/home/user/ml_data/final_W.txt'
    expected_file = '/tests/expected_final_W.txt'

    assert os.path.exists(agent_file), "The file /home/user/ml_data/final_W.txt is missing."
    assert os.path.exists(expected_file), "The expected file /tests/expected_final_W.txt is missing."

    with open(agent_file, 'r') as f:
        agent_lines = [line.strip() for line in f if line.strip()]

    with open(expected_file, 'r') as f:
        expected_lines = [line.strip() for line in f if line.strip()]

    assert len(agent_lines) == 3, f"Expected 3 rows in final_W.txt, found {len(agent_lines)}."

    for row_idx, (agent_line, expected_line) in enumerate(zip(agent_lines, expected_lines)):
        agent_vals = agent_line.split()
        expected_vals = expected_line.split()

        assert len(agent_vals) == 3, f"Expected 3 columns in row {row_idx + 1} of final_W.txt, found {len(agent_vals)}."

        for col_idx, (a_val, e_val) in enumerate(zip(agent_vals, expected_vals)):
            try:
                a_float = float(a_val)
                e_float = float(e_val)
            except ValueError:
                assert False, f"Non-numeric value found at row {row_idx + 1}, column {col_idx + 1}."

            diff = abs(a_float - e_float)
            assert diff <= 1e-4, f"Value mismatch at row {row_idx + 1}, column {col_idx + 1}: expected {e_float}, got {a_float} (diff: {diff})"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
