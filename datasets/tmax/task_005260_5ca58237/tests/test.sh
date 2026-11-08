#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import numpy as np


def test_final_series_mse():
    repo_path = '/home/user/diffusion_sim'
    target_path = os.path.join(repo_path, 'output', 'final_series.npy')
    input_path = os.path.join(repo_path, 'data', 'initial_states.csv')

    assert os.path.isfile(input_path), f"Input file missing at {input_path}"

    # Require the repaired pipeline itself to produce a fresh output.
    if os.path.exists(target_path):
        os.remove(target_path)

    result = subprocess.run(
        ['python3', 'run_sim.py'],
        cwd=repo_path,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"python run_sim.py failed with exit code {result.returncode}:\n{result.stdout}"
    )

    assert os.path.isfile(target_path), f"Agent output file missing at {target_path}"

    try:
        agent_arr = np.load(target_path, allow_pickle=False)
    except Exception as e:
        assert False, f"Failed to load agent output array from {target_path}: {e}"

    # Derive the expected result from the actual rounded CSV values, skipping only
    # malformed sensor rows, then apply the specified stable recurrence.
    initial_states = []
    with open(input_path, 'r') as f:
        for line in f:
            try:
                initial_states.append(float(line.strip()))
            except ValueError:
                continue

    true_arr = np.asarray(initial_states, dtype=float)
    kappa = 0.885
    tau = 1.420
    for _ in range(50):
        denominator = np.abs(true_arr - 2.0) + 1e-8
        true_arr = true_arr - kappa * (true_arr / denominator) * np.exp(-tau)

    assert agent_arr.shape == true_arr.shape, (
        f"Shape mismatch: agent array has shape {agent_arr.shape}, but truth has shape {true_arr.shape}. "
        "Did you drop the corrupted rows correctly?"
    )

    mse = np.mean((agent_arr - true_arr) ** 2)
    threshold = 1e-4

    assert mse <= threshold, (
        f"Output data does not match expected values closely enough.\n"
        f"Measured MSE: {mse}\n"
        f"Threshold: {threshold}\n"
        f"Check that you used the correct kappa and tau values from the image, "
        f"and implemented the correct numerical stability fix in math_core.py."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
