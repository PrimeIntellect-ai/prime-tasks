#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

import h5py
import numpy as np


def expected_stationary_distribution():
    with h5py.File("/home/user/q_matrix.h5", "r") as f:
        q = np.asarray(f["Q"][:], dtype=float)

    # The null space of Q^T is its right-singular vector corresponding
    # to the smallest singular value.
    _, _, vh = np.linalg.svd(q.T)
    pi = vh[-1, :]
    if pi.sum() < 0:
        pi = -pi
    pi = pi / pi.sum()
    assert np.all(pi >= -1e-12)
    return pi


def test_results_exist_and_valid():
    executable = "/home/user/simulator"
    assert os.path.isfile(executable), f"Compiled executable {executable} does not exist. Did you compile the code?"
    assert os.access(executable, os.X_OK), f"File {executable} is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable} is not a compiled executable."

    results_file = "/home/user/results.txt"
    if os.path.exists(results_file):
        os.remove(results_file)

    completed = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"Simulator exited with code {completed.returncode}. stderr: {completed.stderr}"
    )
    assert os.path.isfile(results_file), f"{results_file} does not exist. Did you run the compiled simulator?"

    with open(results_file, "r") as f:
        content = f.read()

    assert "nan" not in content.lower(), "Output contains NaN. The integration likely diverged due to an incorrect step size."

    # Parse KL divergence
    kl_match = re.search(r"KL_Divergence:\s*\[([0-9\.]+)\]", content)
    assert kl_match is not None, "Could not parse KL_Divergence from results.txt. Make sure the format matches exactly."

    kl_value = float(kl_match.group(1))
    assert kl_value < 0.01, f"KL Divergence is too high: {kl_value} (expected < 0.01). The empirical distribution did not converge to the theoretical one."

    # Parse Theoretical
    theo_match = re.search(r"Theoretical:\s*\[([0-9\.,\s]+)\]", content)
    assert theo_match is not None, "Could not parse Theoretical distribution from results.txt."
    theo_vals = [float(x.strip()) for x in theo_match.group(1).split(",")]
    assert len(theo_vals) == 4, f"Theoretical distribution should have 4 values, found {len(theo_vals)}."

    expected_theo = expected_stationary_distribution()
    for v, exp in zip(theo_vals, expected_theo):
        assert abs(v - exp) < 0.01, f"Theoretical distribution value {v} does not match expected {exp}."

    # Parse Empirical
    emp_match = re.search(r"Empirical:\s*\[([0-9\.,\s]+)\]", content)
    assert emp_match is not None, "Could not parse Empirical distribution from results.txt."
    emp_vals = [float(x.strip()) for x in emp_match.group(1).split(",")]
    assert len(emp_vals) == 4, f"Empirical distribution should have 4 values, found {len(emp_vals)}."

    for v, exp in zip(emp_vals, expected_theo):
        assert abs(v - exp) < 0.01, f"Empirical distribution value {v} does not match expected {exp}."


def test_simulator_compiled():
    executable = "/home/user/simulator"
    assert os.path.isfile(executable), f"Compiled executable {executable} does not exist. Did you compile the code?"
    assert os.access(executable, os.X_OK), f"File {executable} is not executable."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
