#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import subprocess

import numpy as np
import pandas as pd
import pytest
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler

SCRIPT_PATH = "/home/user/evaluate_benchmarks.py"
CLEAN_CORPUS_DIR = "/app/corpora/clean/"
EVIL_CORPUS_DIR = "/app/corpora/evil/"
FEATURES = ["latency_ms", "memory_mb", "cpu_util"]
THRESHOLD = 2.85


def test_script_exists():
    """Check if the user script exists."""
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"


def test_clean_corpus():
    """Check that all clean files return exit code 0."""
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv"))
    assert len(clean_files) > 0, f"No clean files found in {CLEAN_CORPUS_DIR}"

    failed_files = []
    for csv_file in clean_files:
        result = subprocess.run(["python3", SCRIPT_PATH, csv_file], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(csv_file))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files failed (expected exit code 0): {failed_files}")


def test_evil_corpus():
    """Check that all evil files return exit code 1."""
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.csv"))
    assert len(evil_files) > 0, f"No evil files found in {EVIL_CORPUS_DIR}"

    failed_files = []
    for csv_file in evil_files:
        result = subprocess.run(["python3", SCRIPT_PATH, csv_file], capture_output=True)
        if result.returncode != 1:
            failed_files.append(os.path.basename(csv_file))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed (expected exit code 1): {failed_files}")


def oracle_exit_code(df):
    values = df[FEATURES].copy()
    values = values.fillna(values.median())
    scaled = StandardScaler().fit_transform(values)
    component = PCA(n_components=1).fit_transform(scaled)
    return 1 if np.max(np.abs(component[:, 0])) > THRESHOLD else 0


def make_candidate(rng, anomalous):
    rows = int(rng.integers(35, 76))
    df = pd.DataFrame({
        "timestamp": pd.date_range("2024-01-01", periods=rows, freq="min"),
        "model_id": [f"model_{secrets.token_hex(3)}"] * rows,
        "latency_ms": rng.normal(rng.uniform(70, 160), rng.uniform(2, 12), rows),
        "memory_mb": rng.normal(rng.uniform(300, 900), rng.uniform(10, 45), rows),
        "cpu_util": rng.normal(rng.uniform(25, 70), rng.uniform(1, 6), rows),
    })

    # Exercise median imputation at unpredictable rows and in different columns.
    for column in FEATURES:
        count = int(rng.integers(1, 4))
        missing_rows = rng.choice(rows, size=count, replace=False)
        df.loc[missing_rows, column] = np.nan

    if anomalous:
        row = int(rng.integers(0, rows))
        df.loc[row, "latency_ms"] = rng.uniform(600, 1200)
        df.loc[row, "memory_mb"] = rng.uniform(2500, 5000)
        df.loc[row, "cpu_util"] = rng.uniform(150, 300)
    return df


def test_dynamically_generated_unlabelled_cases(tmp_path):
    """Classify fresh cases whose paths do not reveal their expected result."""
    rng = np.random.default_rng(secrets.randbits(128))
    cases = []

    for wanted in (0, 1):
        for _ in range(6):
            for _attempt in range(500):
                df = make_candidate(rng, anomalous=(wanted == 1))
                expected = oracle_exit_code(df)
                if expected == wanted:
                    break
            else:
                pytest.fail(f"Could not generate a benchmark case with expected code {wanted}")

            csv_path = tmp_path / f"{secrets.token_hex(16)}.csv"
            df.to_csv(csv_path, index=False)
            cases.append((csv_path, expected))

    rng.shuffle(cases)
    failures = []
    for csv_path, expected in cases:
        result = subprocess.run(
            ["python3", SCRIPT_PATH, str(csv_path)],
            capture_output=True,
            timeout=20,
        )
        if result.returncode != expected:
            failures.append((csv_path.name, expected, result.returncode))

    assert not failures, f"Incorrect results on dynamically generated cases: {failures}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
