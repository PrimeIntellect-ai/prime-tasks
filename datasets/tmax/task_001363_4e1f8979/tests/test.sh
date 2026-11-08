#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import math

def test_bad_commit_identified():
    repo_path = "/home/user/timeseries_proj"
    bad_commit_file = "/home/user/bad_commit.txt"

    assert os.path.exists(bad_commit_file), f"File {bad_commit_file} was not found."

    with open(bad_commit_file, "r") as f:
        agent_commit = f.read().strip()

    # Find the 150th commit dynamically
    try:
        log = subprocess.check_output(
            ["git", "-C", repo_path, "log", "--reverse", "--pretty=format:%H"],
            text=True
        ).strip().split('\n')
    except subprocess.CalledProcessError as e:
        assert False, f"Failed to get git log: {e}"

    assert len(log) >= 150, "Repository does not have 150 commits."
    expected_bad_commit = log[149]  # 150th commit (0-indexed)

    assert agent_commit == expected_bad_commit, (
        f"Incorrect bad commit identified. "
        f"Expected {expected_bad_commit}, but got {agent_commit}."
    )

def test_fixed_calc_var_accuracy():
    fixed_script = "/home/user/fixed_calc_var.py"
    ref_binary = "/app/ref_calc"

    assert os.path.exists(fixed_script), f"Fixed script {fixed_script} was not found."
    assert os.access(ref_binary, os.X_OK), f"Reference binary {ref_binary} is not executable."

    max_err = 0.0
    random.seed(42)  # For reproducibility in tests

    for _ in range(10):
        seed = str(random.uniform(1.0, 100.0))

        try:
            ref_out = subprocess.check_output([ref_binary, seed], text=True).strip()
            ref_val = float(ref_out)
        except Exception as e:
            assert False, f"Failed to run reference binary or parse output: {e}"

        try:
            agent_out = subprocess.check_output(['python3', fixed_script, seed], text=True).strip()
            agent_val = float(agent_out)
        except Exception as e:
            assert False, f"Failed to run fixed script or parse output: {e}"

        assert math.isfinite(ref_val), f"Reference produced a non-finite value for seed {seed}: {ref_val}"
        assert math.isfinite(agent_val), f"Fixed script produced a non-finite value for seed {seed}: {agent_val}"

        err = abs(ref_val - agent_val)
        assert math.isfinite(err), f"Computed error is non-finite for seed {seed}: {err}"
        if err > max_err:
            max_err = err

    assert max_err < 1e-7, (
        f"Maximum absolute error {max_err} exceeds strict threshold of 1e-7. "
        "The floating-point precision regression is not fully resolved."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
