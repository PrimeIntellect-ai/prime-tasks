#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess


def expected_metric(preds_list, truths_list, ages_list):
    total = 0.0
    for pred_s, truth_s, age_s in zip(preds_list, truths_list, ages_list):
        pred = float(pred_s)
        truth = float(truth_s)
        age = int(age_s)

        if age < 18:
            weight = 2.5
        elif age <= 65:
            weight = 1.0
        else:
            weight = 1.8

        diff = pred - truth
        total += diff * diff * weight

    return f"{total / len(preds_list):.5f}"


def test_evaluator_fuzz_equivalence():
    agent_bin = "/home/user/evaluator"

    assert os.path.exists(agent_bin), f"Agent binary not found exactly at {agent_bin}"
    assert os.path.isfile(agent_bin), f"Path {agent_bin} is not a file"
    assert os.access(agent_bin, os.X_OK), f"Agent binary at {agent_bin} is not executable"

    random.seed(42)

    for i in range(100):
        n = random.randint(5, 100)

        preds_list = [f"{random.uniform(-10.0, 10.0):.6f}" for _ in range(n)]
        truths_list = [f"{random.uniform(-10.0, 10.0):.6f}" for _ in range(n)]
        ages_list = [str(random.randint(5, 90)) for _ in range(n)]

        preds = ",".join(preds_list)
        truths = ",".join(truths_list)
        ages = ",".join(ages_list)
        expected = expected_metric(preds_list, truths_list, ages_list)

        agent_proc = subprocess.run(
            [agent_bin, preds, truths, ages],
            capture_output=True,
            text=True,
        )

        assert agent_proc.returncode == 0, (
            f"Agent binary failed on iteration {i} with stderr: {agent_proc.stderr}"
        )

        agent_out = agent_proc.stdout.strip()
        assert agent_out == expected, (
            f"Mismatch on iteration {i}.\n"
            f"Inputs (N={n}):\n"
            f"  preds: {preds[:100]}...\n"
            f"  truths: {truths[:100]}...\n"
            f"  ages: {ages[:100]}...\n"
            f"Expected: '{expected}'\n"
            f"Got (Agent): '{agent_out}'"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
