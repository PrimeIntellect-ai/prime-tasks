#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random


def reference_roots():
    rng = random.Random(42)
    roots = []
    K = 4.25
    for _ in range(1000):
        x = rng.uniform(0.1, 5.0)
        for _ in range(100):
            deriv = 3 * x**2 - K
            if deriv == 0:
                x = float("nan")
                break
            x = x - (x**3 - K * x + 1) / deriv
        roots.append(x)
    return roots


def test_roots_accuracy():
    agent_file = "/home/user/roots.txt"
    assert os.path.exists(agent_file), f"Agent output file not found: {agent_file}"

    with open(agent_file, "r") as f:
        agent_lines = [line.strip() for line in f if line.strip()]

    truth_values = reference_roots()
    assert len(agent_lines) == 1000, f"Expected 1000 lines in {agent_file}, got {len(agent_lines)}"
    assert len(truth_values) == 1000

    max_err = 0.0
    for agent_val, truth_val in zip(agent_lines, truth_values):
        if math.isnan(truth_val):
            if agent_val != "NaN":
                max_err = max(max_err, 999.0)
            continue

        if agent_val == "NaN":
            max_err = max(max_err, 999.0)
            continue

        try:
            a_float = float(agent_val)
        except ValueError:
            max_err = max(max_err, 999.0)
            continue

        if not math.isfinite(a_float):
            max_err = max(max_err, 999.0)
            continue

        err = abs(a_float - truth_val)
        max_err = max(max_err, err)

    assert max_err <= 1e-5, (
        f"Maximum Absolute Error {max_err} exceeds threshold 1e-5. "
        "The calculated roots are not accurate enough."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
