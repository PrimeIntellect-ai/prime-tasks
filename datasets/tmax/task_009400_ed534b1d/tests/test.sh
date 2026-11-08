#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import uuid

import numpy as np
import pytest
from scipy.stats import wasserstein_distance


def load_submission():
    path = "/home/user/mcmc_gc.py"
    name = "mcmc_gc_submission_" + uuid.uuid4().hex
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_results_file_exists_and_valid():
    results_path = "/home/user/results.txt"
    assert os.path.exists(results_path), f"{results_path} does not exist. Did you run the pipeline?"
    assert os.path.isfile(results_path), f"{results_path} is not a file."

    with open(results_path, "r") as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"{results_path} does not contain a valid float. Found: {content}")

    assert 0.01 <= val <= 0.08, f"Wasserstein distance {val} in {results_path} is outside expected bounds [0.01, 0.08]."


def test_mcmc_script_exists():
    script_path = "/home/user/mcmc_gc.py"
    assert os.path.exists(script_path), f"{script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."


def test_run_pipeline_script_exists():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.exists(script_path), f"{script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."


def test_test_mcmc_script_exists_and_passes():
    script_path = "/home/user/test_mcmc.py"
    assert os.path.exists(script_path), f"{script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."

    result = subprocess.run(
        [sys.executable, "-m", "pytest", script_path],
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, f"pytest {script_path} failed. Output:\n{result.stdout}\n{result.stderr}"


def test_evaluate_posterior_matches_required_calculation():
    module = load_submission()
    assert callable(getattr(module, "evaluate_posterior", None))

    samples = np.array([0.401, 0.417, 0.438, 0.466, 0.492, 0.499], dtype=float)
    np.random.seed(99)
    reference = np.random.uniform(0.4, 0.5, size=len(samples))
    expected = wasserstein_distance(samples, reference)

    np.random.seed(123456)
    actual = module.evaluate_posterior(samples.copy())
    assert np.isscalar(actual)
    assert np.isfinite(actual)
    assert float(actual) == pytest.approx(float(expected), abs=1e-12, rel=1e-12)


def test_run_mcmc_is_reproducible_and_uses_input_data():
    module = load_submission()
    run_mcmc = getattr(module, "run_mcmc", None)
    assert callable(run_mcmc)

    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
    cases = [(0.34, 0.07), (0.67, 0.12)]
    posterior_summaries = []

    with tempfile.TemporaryDirectory() as td:
        for index, (center, spread) in enumerate(cases):
            data = np.clip(rng.normal(center, spread, size=120), 0.0, 1.0)
            path = os.path.join(td, f"case_{index}.npy")
            np.save(path, data)

            np.random.seed(987654)
            mu1, sigma1 = run_mcmc(path, iterations=4000, seed=731 + index)
            np.random.seed(123)
            mu2, sigma2 = run_mcmc(path, iterations=4000, seed=731 + index)

            assert isinstance(mu1, np.ndarray), "mu samples must be a numpy array"
            assert isinstance(sigma1, np.ndarray), "sigma samples must be a numpy array"
            assert mu1.shape == (2000,)
            assert sigma1.shape == (2000,)
            assert np.array_equal(mu1, mu2), "run_mcmc is not reproducible for a fixed seed"
            assert np.array_equal(sigma1, sigma2), "run_mcmc is not reproducible for a fixed seed"
            assert np.all(np.isfinite(mu1)) and np.all(np.isfinite(sigma1))
            assert np.all((mu1 >= 0.0) & (mu1 <= 1.0))
            assert np.all((sigma1 >= 0.01) & (sigma1 <= 0.5))

            changed = (np.diff(mu1) != 0) | (np.diff(sigma1) != 0)
            unchanged = (np.diff(mu1) == 0) & (np.diff(sigma1) == 0)
            assert np.count_nonzero(changed) >= 5, "the returned chain does not contain MCMC moves"
            assert np.count_nonzero(unchanged) >= 5, "the returned chain does not show MH rejections"

            empirical_mu = float(np.mean(data))
            empirical_sigma = float(np.std(data, ddof=0))
            posterior_mu = float(np.mean(mu1))
            posterior_sigma = float(np.mean(sigma1))
            assert abs(posterior_mu - empirical_mu) < 0.035
            assert abs(posterior_sigma - empirical_sigma) < 0.04
            posterior_summaries.append(posterior_mu)

        assert posterior_summaries[1] - posterior_summaries[0] > 0.20, "run_mcmc does not respond to the supplied data"

        probe = np.clip(rng.normal(0.55, 0.09, size=100), 0.0, 1.0)
        probe_path = os.path.join(td, "seed_probe.npy")
        np.save(probe_path, probe)
        mu_a, sigma_a = run_mcmc(probe_path, iterations=1200, seed=11)
        mu_b, sigma_b = run_mcmc(probe_path, iterations=1200, seed=12)
        assert not (np.array_equal(mu_a, mu_b) and np.array_equal(sigma_a, sigma_b)), "the seed argument has no effect"


def test_pipeline_executes_submission_and_writes_computed_result():
    results_path = "/home/user/results.txt"
    if os.path.exists(results_path):
        os.remove(results_path)

    result = subprocess.run(
        ["/bin/bash", "/home/user/run_pipeline.sh"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=240,
    )
    assert result.returncode == 0, f"run_pipeline.sh failed. Output:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(results_path), "run_pipeline.sh did not create results.txt"

    with open(results_path, "r") as f:
        content = f.read().strip()
    assert re.fullmatch(r"[-+]?(?:\d+\.\d{4})", content), "results.txt must contain only a float rounded to 4 decimal places"

    module = load_submission()
    mu_samples, sigma_samples = module.run_mcmc(
        "/home/user/gc_data.npy", iterations=10000, seed=42
    )
    assert mu_samples.shape == (5000,)
    assert sigma_samples.shape == (5000,)
    expected = float(module.evaluate_posterior(mu_samples))
    assert content == f"{expected:.4f}", "results.txt is not the result produced by the submitted MCMC pipeline"

    val = float(content)
    assert 0.01 <= val <= 0.08, f"Wasserstein distance {val} in {results_path} is outside expected bounds [0.01, 0.08]."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
