#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math

def test_solution_file_exists():
    """Verify that the solution file exists."""
    file_path = "/home/user/solution.txt"
    assert os.path.isfile(file_path), f"Solution file {file_path} is missing."

def test_solution_content():
    """Verify the content of the solution file."""
    file_path = "/home/user/solution.txt"
    with open(file_path, 'r') as f:
        content = f.read().strip()

    parts = content.split(',')
    assert len(parts) == 2, f"Expected 2 comma-separated values in {file_path}, found {len(parts)}."

    try:
        w0 = float(parts[0])
        w1 = float(parts[1])
    except ValueError:
        assert False, f"Could not parse '{parts[0]}' and '{parts[1]}' as floats."

    # Due to SVD sign ambiguity, the principal components might be multiplied by -1.
    # Therefore, the optimal weights might have flipped signs.
    # We check the absolute values.
    expected_abs_w0 = 0.0381
    expected_abs_w1 = 0.3621

    assert math.isclose(abs(w0), expected_abs_w0, abs_tol=0.001), \
        f"Expected absolute value of w0 to be close to {expected_abs_w0}, got {abs(w0)}"
    assert math.isclose(abs(w1), expected_abs_w1, abs_tol=0.001), \
        f"Expected absolute value of w1 to be close to {expected_abs_w1}, got {abs(w1)}"

    # Also verify formatting (4 decimal places)
    assert len(parts[0].split('.')[-1]) == 4, f"Expected w0 to be rounded to 4 decimal places, got {parts[0]}"
    assert len(parts[1].split('.')[-1]) == 4, f"Expected w1 to be rounded to 4 decimal places, got {parts[1]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
