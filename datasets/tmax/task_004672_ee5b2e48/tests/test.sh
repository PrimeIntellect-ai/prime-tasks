#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

import numpy as np
import pandas as pd
import pytest
from scipy.optimize import root

CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"
CLASSIFIER_SCRIPT = "/home/user/classifier.py"


def run_classifier(csv_path):
    assert os.path.exists(CLASSIFIER_SCRIPT), f"Classifier script not found at {CLASSIFIER_SCRIPT}"
    assert os.path.isfile(CLASSIFIER_SCRIPT), f"Classifier path is not a regular file: {CLASSIFIER_SCRIPT}"
    result = subprocess.run(
        ["python3", CLASSIFIER_SCRIPT, csv_path],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Script failed with exit code {result.returncode} for {csv_path}. Stderr: {result.stderr}"
    return result.stdout.strip()


def test_clean_corpus():
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.csv')]
    assert len(clean_files) > 0, "No clean CSV files found."

    failed_files = []
    for f in clean_files:
        path = os.path.join(CLEAN_CORPUS_DIR, f)
        output = run_classifier(path)
        if output != "CLEAN":
            failed_files.append((f, output))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(clean_files)} clean files rejected or invalid output.\n"
        for f, out in failed_files[:5]:
            error_msg += f"File: {f}, Output: {out}\n"
        pytest.fail(error_msg)


def test_evil_corpus():
    assert os.path.exists(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.csv')]
    assert len(evil_files) > 0, "No evil CSV files found."

    failed_files = []
    for f in evil_files:
        path = os.path.join(EVIL_CORPUS_DIR, f)
        output = run_classifier(path)
        if output != "EVIL":
            failed_files.append((f, output))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(evil_files)} evil files bypassed or invalid output.\n"
        for f, out in failed_files[:5]:
            error_msg += f"File: {f}, Output: {out}\n"
        pytest.fail(error_msg)


def theoretical_parameters():
    def equations(v):
        x, y = v
        return np.array([x**3 - 3*x - y, y**2 - x - 2], dtype=float)

    solved = root(equations, np.array([1.8, 1.8], dtype=float))
    assert solved.success
    mu = solved.x
    assert np.all(mu > 0)
    assert np.max(np.abs(equations(mu))) < 1e-9

    x, y = mu
    precision = np.array([[3*x*x - 3, -1], [-1, 2*y]], dtype=float)
    covariance = np.linalg.inv(precision)
    return mu, covariance


def trace_with_exact_moments(rng, mean, covariance, n=1200):
    raw = rng.normal(size=(n, 2))
    raw -= raw.mean(axis=0)
    raw_covariance = np.cov(raw, rowvar=False, ddof=1)
    eigenvalues, eigenvectors = np.linalg.eigh(raw_covariance)
    whiten = eigenvectors @ np.diag(1.0 / np.sqrt(eigenvalues)) @ eigenvectors.T
    standardized = raw @ whiten
    chol = np.linalg.cholesky(covariance)
    return standardized @ chol.T + mean


def expected_for_contents(data, mu, covariance):
    sample_mean = np.mean(data, axis=0)
    sample_covariance = np.cov(data, rowvar=False, ddof=1)
    if (np.all(np.abs(sample_mean - mu) <= 0.4) and
            np.all(np.abs(sample_covariance - covariance) <= 0.4)):
        return "CLEAN"
    return "EVIL"


def test_generated_holdout_uses_csv_contents(tmp_path):
    mu, covariance = theoretical_parameters()
    rng = np.random.default_rng(int.from_bytes(secrets.token_bytes(8), "big"))

    cases = []
    for _ in range(2):
        cases.append(trace_with_exact_moments(rng, mu, covariance))
        cases.append(trace_with_exact_moments(rng, mu + np.array([0.65, 0.0]), covariance))
        bad_covariance = covariance + np.array([[0.55, 0.0], [0.0, 0.0]])
        cases.append(trace_with_exact_moments(rng, mu, bad_covariance))

    secrets.SystemRandom().shuffle(cases)
    expectations = [expected_for_contents(data, mu, covariance) for data in cases]
    assert "CLEAN" in expectations and "EVIL" in expectations

    # Every case uses the identical neutral path, so directory or filename-based
    # classification cannot distinguish clean traces from corrupted traces.
    csv_path = tmp_path / "trace.csv"
    for data, expected in zip(cases, expectations):
        pd.DataFrame(data, columns=["x", "y"]).to_csv(csv_path, index=False)
        output = run_classifier(str(csv_path))
        assert output == expected, (
            f"Generated holdout was misclassified: expected {expected}, got {output!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
