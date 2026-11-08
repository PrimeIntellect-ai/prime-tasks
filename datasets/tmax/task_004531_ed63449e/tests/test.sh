#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import math
import re


def test_entropy_result():
    result_file = "/home/user/entropy_result.txt"
    assert os.path.exists(result_file), f"Result file is missing at {result_file}"
    assert os.path.isfile(result_file), f"Path {result_file} is not a file"

    with open(result_file, "r") as f:
        content = f.read().strip()

    assert content, f"File {result_file} is empty"
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", content), \
        f"Content of {result_file} is not a single numerical float: {content}"

    try:
        agent_val = float(content)
    except ValueError:
        assert False, f"Content of {result_file} is not a valid float: {content}"

    assert math.isfinite(agent_val), f"Result must be finite, got: {content}"

    target = 0.937636
    error = abs(agent_val - target)
    assert error <= 0.05, f"Metric threshold failed: error {error} > 0.05. Agent value: {agent_val}, Target: {target}"

    weights = (15, 25, 60)
    total = sum(weights)
    probabilities = [weight / total for weight in weights]
    expected = -sum(p * math.log(p) for p in probabilities)
    assert math.isclose(agent_val, expected, rel_tol=0.0, abs_tol=1e-6), \
        f"Incorrect entropy: got {agent_val}, expected {expected}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
