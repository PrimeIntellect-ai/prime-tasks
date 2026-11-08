#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
from scipy.integrate import quad
from scipy.stats import beta


def correct_probability():
    # Beta(1 + successes, 1 + failures)
    posterior_a = (411, 91)
    posterior_b = (426, 76)
    probability, _ = quad(
        lambda theta_b: beta.pdf(theta_b, *posterior_b) * beta.cdf(theta_b, *posterior_a),
        0.0,
        1.0,
        epsabs=1e-13,
        epsrel=1e-13,
        limit=200,
    )
    return f"{probability:.4f}"


def test_prob_file():
    """Test that prob.txt contains the correct probability."""
    file_path = "/home/user/prob.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected = correct_probability()
    assert content == expected, f"Expected prob.txt to contain '{expected}', but got '{content}'."


def test_decision_file():
    """Test that decision.txt contains the correct decision."""
    file_path = "/home/user/decision.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == "RETAIN", f"Expected decision.txt to contain 'RETAIN', but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
