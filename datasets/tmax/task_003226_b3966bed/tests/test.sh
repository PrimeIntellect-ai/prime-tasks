#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import subprocess
import sys
import warnings

import numpy as np
import pytest

MF_PATH = "/home/user/mf.py"
MSE_PATH = "/home/user/mse.txt"


def reference_nmf(V, k, max_iter=1000):
    np.random.seed(0)
    n, m = V.shape
    W = np.random.rand(n, k)
    H = np.random.rand(k, m)
    for _ in range(max_iter):
        H = H * (W.T @ V) / (W.T @ W @ H + 1e-9)
        W = W * (V @ H.T) / (W @ H @ H.T + 1e-9)
    return W, H


def load_submission():
    assert os.path.isfile(MF_PATH), "Missing NMF script."
    spec = importlib.util.spec_from_file_location("submitted_mf", MF_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "nmf", None)), "/home/user/mf.py must define nmf."
    return module


def get_expected_mse():
    V_noisy = np.loadtxt('/home/user/noisy_data.csv', delimiter=',')
    V_ref = np.loadtxt('/home/user/reference.csv', delimiter=',')
    W, H = reference_nmf(V_noisy, k=5, max_iter=1000)
    return f"{np.mean((W @ H - V_ref) ** 2):.4f}"


def test_mf_script_modifications():
    assert os.path.isfile(MF_PATH), "Missing NMF script."
    with open(MF_PATH, 'r') as f:
        content = f.read()
    assert "1e-9" in content, "The script /home/user/mf.py does not contain the epsilon '1e-9' to prevent division by zero."


def test_nmf_preserves_seed_and_initialization():
    module = load_submission()
    V = np.arange(24, dtype=float).reshape(6, 4) / 10.0
    expected_W, expected_H = reference_nmf(V, k=3, max_iter=0)
    actual_W, actual_H = module.nmf(V.copy(), k=3, max_iter=0)
    np.testing.assert_allclose(actual_W, expected_W, rtol=0, atol=0)
    np.testing.assert_allclose(actual_H, expected_H, rtol=0, atol=0)


def test_nmf_uses_stable_updates_and_produces_finite_results():
    module = load_submission()
    rng = np.random.default_rng(73129)
    inputs = [
        (rng.random((9, 7)), 4, 6),
        (np.vstack([rng.random((5, 6)), np.zeros((1, 6))]), 3, 8),
        (np.zeros((4, 5), dtype=float), 2, 3),
    ]

    for V, k, max_iter in inputs:
        expected_W, expected_H = reference_nmf(V.copy(), k, max_iter)
        with warnings.catch_warnings():
            warnings.simplefilter("error")
            actual_W, actual_H = module.nmf(V.copy(), k=k, max_iter=max_iter)

        actual_W = np.asarray(actual_W)
        actual_H = np.asarray(actual_H)
        assert actual_W.shape == expected_W.shape
        assert actual_H.shape == expected_H.shape
        assert np.isfinite(actual_W).all(), "nmf produced non-finite values in W."
        assert np.isfinite(actual_H).all(), "nmf produced non-finite values in H."
        np.testing.assert_allclose(actual_W, expected_W, rtol=1e-12, atol=1e-12)
        np.testing.assert_allclose(actual_H, expected_H, rtol=1e-12, atol=1e-12)


def test_mf_script_runs_without_division_warnings():
    env = os.environ.copy()
    env["PYTHONWARNINGS"] = "error"
    result = subprocess.run(
        [sys.executable, MF_PATH],
        cwd="/home/user",
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        "Running /home/user/mf.py failed or emitted a warning: "
        + result.stdout + result.stderr
    )


def test_mse_file_exists():
    assert os.path.isfile(MSE_PATH), f"Missing MSE output file: {MSE_PATH}"


def test_mse_value_correct():
    assert os.path.isfile(MSE_PATH), "Missing MSE output file."
    with open(MSE_PATH, 'r') as f:
        actual_val = f.read().strip()
    expected_val = get_expected_mse()
    assert actual_val == expected_val, (
        f"MSE value in {MSE_PATH} is incorrect. Expected {expected_val}, got {actual_val}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
