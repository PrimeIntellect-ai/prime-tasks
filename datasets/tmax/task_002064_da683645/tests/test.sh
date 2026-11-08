#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import sys

import h5py
import numpy as np
import pytest

NOTEBOOK_PATH = "/home/user/mcmc_fit.ipynb"
POSTERIOR_PATH = "/home/user/posterior.h5"
ALPHA_MEAN_PATH = "/home/user/alpha_mean.txt"


def reference_chain():
    """Independently reproduce the required deterministic MCMC calculation."""
    t_obs = np.linspace(0, 5, 50)
    y_true = (1 - 1.0 / 2.0) * np.exp(-2.0 * t_obs) + 1.0 / 2.0
    observation_rng = np.random.RandomState(42)
    y_obs = y_true + observation_rng.normal(0, 0.05, size=len(t_obs))

    def integrate_ode(alpha, beta, t_eval):
        dt = 0.01
        y = np.zeros(len(t_eval))
        y[0] = 1.0
        y_curr = 1.0
        t_curr = t_eval[0]
        idx = 1
        while idx < len(t_eval):
            while t_curr < t_eval[idx]:
                step = min(dt, t_eval[idx] - t_curr)
                y_curr = y_curr + step * (-alpha * y_curr ** 3 + beta)
                t_curr += step
            y[idx] = y_curr
            idx += 1
        return y

    def log_likelihood(theta):
        alpha, beta = theta
        if alpha < 0 or beta < 0:
            return -np.inf
        try:
            y_pred = integrate_ode(alpha, beta, t_obs)
            if np.any(np.isnan(y_pred)) or np.any(np.isinf(y_pred)):
                return -np.inf
            sigma = 0.05
            return -0.5 * np.sum(((y_obs - y_pred) / sigma) ** 2)
        except Exception:
            return -np.inf

    rng = np.random.RandomState(123)
    chain = np.zeros((1000, 2))
    theta_curr = np.array([1.5, 0.5])
    ll_curr = log_likelihood(theta_curr)

    for i in range(1000):
        theta_prop = theta_curr + rng.normal(0, 0.05, size=2)
        ll_prop = log_likelihood(theta_prop)
        if np.log(rng.rand()) < ll_prop - ll_curr:
            theta_curr = theta_prop
            ll_curr = ll_prop
        chain[i] = theta_curr

    return chain


def test_notebook_fixed():
    """Check that the notebook has been updated to use dt = 0.01."""
    assert os.path.isfile(NOTEBOOK_PATH), f"Notebook file is missing: {NOTEBOOK_PATH}"

    with open(NOTEBOOK_PATH, "r") as f:
        try:
            nb = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Notebook is not a valid JSON file.")

    code_content = ""
    for cell in nb.get("cells", []):
        if cell.get("cell_type") == "code":
            source = cell.get("source", [])
            if isinstance(source, list):
                source = "".join(source)
            code_content += source

    assert "dt = 0.01" in code_content, "The notebook does not contain the corrected 'dt = 0.01' statement."
    assert "dt = 0.5" not in code_content, "The notebook still contains the buggy 'dt = 0.5' statement."


def test_execute_notebook_and_validate_posterior():
    """Execute the submitted notebook and validate its newly generated chain."""
    if os.path.lexists(POSTERIOR_PATH):
        os.unlink(POSTERIOR_PATH)
    executed_path = "/tmp/executed_mcmc_fit.ipynb"
    if os.path.exists(executed_path):
        os.unlink(executed_path)

    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "jupyter",
            "nbconvert",
            "--to",
            "notebook",
            "--execute",
            NOTEBOOK_PATH,
            "--output",
            "executed_mcmc_fit.ipynb",
            "--output-dir",
            "/tmp",
            "--ExecutePreprocessor.timeout=180",
        ],
        capture_output=True,
        text=True,
        timeout=240,
    )
    assert result.returncode == 0, (
        "The notebook failed during headless execution.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.isfile(POSTERIOR_PATH), (
        f"Posterior file is missing after notebook execution: {POSTERIOR_PATH}"
    )

    try:
        with h5py.File(POSTERIOR_PATH, "r") as f:
            assert "chain" in f, "Dataset 'chain' not found in posterior.h5."
            chain = f["chain"][:]
    except (OSError, ValueError) as exc:
        pytest.fail(f"posterior.h5 is corrupted or not a valid HDF5 file: {exc}")

    assert chain.shape == (1000, 2), (
        f"Dataset 'chain' has an unexpected shape. Expected (1000, 2), got {chain.shape}."
    )
    assert np.all(np.isfinite(chain)), "Dataset 'chain' contains NaN or infinite values."

    expected = reference_chain()
    np.testing.assert_allclose(
        chain,
        expected,
        rtol=0,
        atol=1e-12,
        err_msg="The generated chain does not match the deterministic MCMC result.",
    )


def test_alpha_mean_correct():
    """Check the reported alpha mean against the verified and reference chains."""
    assert os.path.isfile(ALPHA_MEAN_PATH), f"alpha_mean.txt is missing: {ALPHA_MEAN_PATH}"
    with open(ALPHA_MEAN_PATH, "r") as f:
        student_val = f.read().strip()

    assert re.fullmatch(r"-?\d+\.\d{2}", student_val), (
        "alpha_mean.txt must contain one numeric value rounded to exactly 2 decimal places."
    )

    with h5py.File(POSTERIOR_PATH, "r") as f:
        generated_chain = f["chain"][:]
    generated_value = f"{np.mean(generated_chain[100:, 0]):.2f}"
    expected_value = f"{np.mean(reference_chain()[100:, 0]):.2f}"

    assert student_val == generated_value, (
        f"Incorrect mean value in alpha_mean.txt. Expected '{generated_value}', but got '{student_val}'."
    )
    assert student_val == expected_value, (
        f"alpha_mean.txt does not match the deterministic expected result '{expected_value}'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
