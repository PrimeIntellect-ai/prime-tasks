#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import numpy as np
from scipy.stats import kstest, norm, expon


def test_best_fit_log_exists():
    """Test that the output file best_fit.log exists."""
    output_file = '/home/user/best_fit.log'
    assert os.path.exists(output_file), f"Output file {output_file} is missing."
    assert os.path.isfile(output_file), f"{output_file} is not a file."


def test_best_fit_log_contents():
    """Test that the output file contains the correct expected result."""
    output_file = '/home/user/best_fit.log'
    assert os.path.exists(output_file), f"Output file {output_file} is missing."

    np.random.seed(42)
    lengths = np.random.normal(500, 50, 1000).astype(int)

    mu, std = norm.fit(lengths)
    _, p_n = kstest(lengths, 'norm', args=(mu, std))

    loc, scale = expon.fit(lengths)
    _, p_e = kstest(lengths, 'expon', args=(loc, scale))

    best_dist = 'normal' if p_n > p_e else 'exponential'
    best_p = p_n if p_n > p_e else p_e
    expected_content = f"{best_dist},{best_p:.4f}"

    with open(output_file, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Contents of {output_file} do not match the expected result.\n"
        f"Expected: '{expected_content}'\n"
        f"Actual: '{actual_content}'"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
