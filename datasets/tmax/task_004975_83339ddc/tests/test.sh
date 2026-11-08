#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import stat
import subprocess

import numpy as np


def test_sampler_builds_runs_and_produces_mcmc_samples():
    source = "/home/user/mcmc_sampler.cpp"
    samples_path = "/home/user/samples.csv"
    executable = "/home/user/mcmc_sampler"

    assert os.path.exists(source), f"File {source} is missing."
    mode = os.stat(source).st_mode
    assert stat.S_ISREG(mode), f"File {source} must be a regular C++ source file."

    for path in (samples_path, executable):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    compile_result = subprocess.run(
        ["g++", "-O3", "-I", "/usr/include/eigen3", "mcmc_sampler.cpp", "-o", "mcmc_sampler"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, "Compilation failed:\n" + compile_result.stdout
    assert os.path.isfile(executable) and os.access(executable, os.X_OK), "Compiled sampler is missing or not executable."

    run_result = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert run_result.returncode == 0, "Sampler execution failed:\n" + run_result.stdout
    assert os.path.exists(samples_path), f"File {samples_path} is missing. Did you save the samples?"

    with open(samples_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 10000, f"Expected exactly 10,000 samples, found {len(lines)}."

    rows = []
    for i, line in enumerate(lines):
        cols = line.split(',')
        assert len(cols) == 3, f"Expected 3 columns on line {i + 1}, found {len(cols)}."
        try:
            row = [float(value) for value in cols]
        except ValueError:
            raise AssertionError(f"Could not parse values as floats on line {i + 1}: {line}")
        assert all(math.isfinite(value) for value in row), f"Non-finite value on line {i + 1}: {line}"
        rows.append(row)

    samples = np.asarray(rows, dtype=float)
    data = np.loadtxt("/home/user/data.csv", delimiter=",")
    assert data.shape == (100, 4), f"Unexpected data shape: {data.shape}"
    X = data[:, :3]
    y = data[:, 3]

    # Derive the Gaussian posterior from the supplied data rather than trusting
    # a target file in the agent image.
    precision = X.T @ X + 10.0 * np.eye(3)
    posterior_cov = np.linalg.inv(precision)
    posterior_mean = posterior_cov @ X.T @ y

    empirical_mean = samples.mean(axis=0)
    l2_distance = float(np.linalg.norm(empirical_mean - posterior_mean))
    assert l2_distance < 0.1, (
        f"L2 distance between empirical mean {empirical_mean.tolist()} and "
        f"theoretical mean {posterior_mean.tolist()} is {l2_distance:.4f}, which is >= 0.1."
    )

    # A posterior chain must have the covariance implied by the likelihood and
    # prior; a constant file at the posterior mean cannot satisfy this.
    empirical_cov = np.cov(samples, rowvar=False, ddof=1)
    evals, evecs = np.linalg.eigh(posterior_cov)
    whitening = np.diag(1.0 / np.sqrt(evals)) @ evecs.T
    whitened_cov = whitening @ empirical_cov @ whitening.T
    covariance_ratios = np.linalg.eigvalsh(whitened_cov)
    assert np.all((covariance_ratios > 0.30) & (covariance_ratios < 2.50)), (
        "Sample covariance is inconsistent with the Bayesian posterior; "
        f"whitened covariance eigenvalues were {covariance_ratios.tolist()}."
    )

    # Random-walk MH records the current state after both acceptances and
    # rejections. It should therefore contain exact repeats as well as accepted
    # Gaussian-sized moves, unlike an arbitrary cloud or repeated mean.
    deltas = np.diff(samples, axis=0)
    changed = np.any(deltas != 0.0, axis=1)
    changed_fraction = float(changed.mean())
    assert 0.15 < changed_fraction < 0.90, (
        "The output does not exhibit a plausible Random Walk Metropolis-Hastings "
        f"accept/reject pattern; changed-state fraction was {changed_fraction:.4f}."
    )

    accepted_deltas = deltas[changed]
    component_msd = np.mean(accepted_deltas ** 2, axis=0)
    assert np.all((component_msd > 0.0003) & (component_msd < 0.02)), (
        "Accepted transition sizes are inconsistent with a Gaussian proposal "
        f"having covariance 0.01 I; component mean squared moves were {component_msd.tolist()}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
