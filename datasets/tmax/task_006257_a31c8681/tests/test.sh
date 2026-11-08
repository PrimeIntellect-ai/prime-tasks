#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import re
import subprocess

import numpy as np
import pandas as pd
import pytest
from scipy import stats
from sklearn.impute import SimpleImputer
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

PIPELINE = "/home/user/pipeline.py"
DATASET = "/home/user/dataset.csv"
OUTPUT = "/home/user/ci_output.txt"


def expected_processing(df):
    X = df.drop(columns=["Target"])
    y = df["Target"]
    X_train_raw, X_test_raw, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    imputer = SimpleImputer(strategy="mean")
    X_train_imputed = imputer.fit_transform(X_train_raw)
    X_test_imputed = imputer.transform(X_test_raw)
    scaler = StandardScaler()
    X_train = scaler.fit_transform(X_train_imputed)
    X_test = scaler.transform(X_test_imputed)
    return X_train, X_test, y_train, y_test


def expected_ci(df):
    _, X_test, _, _ = expected_processing(df)
    values = X_test[:, 0]
    lower, upper = stats.t.interval(
        0.95, len(values) - 1, loc=np.mean(values), scale=stats.sem(values)
    )
    return f"{lower:.4f},{upper:.4f}"


def run_pipeline():
    result = subprocess.run(
        ["python3", PIPELINE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"pipeline.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(PIPELINE), "The file /home/user/pipeline.py does not exist."
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    run_pipeline()
    assert os.path.isfile(OUTPUT), (
        "Running /home/user/pipeline.py did not create /home/user/ci_output.txt."
    )


def test_ci_output_exists():
    """Verify that the ci_output.txt file exists."""
    assert os.path.isfile(OUTPUT), "The file /home/user/ci_output.txt does not exist."


def test_ci_output_content():
    """Verify that the confidence interval output is correct."""
    with open(OUTPUT, "r") as f:
        raw = f.read()
    content = raw.strip()

    assert re.fullmatch(r"[+-]?\d+\.\d{4},[+-]?\d+\.\d{4}\n?", raw), (
        "The file must contain exactly one line with two comma-separated numbers, "
        "each rounded to four decimal places."
    )
    parts = content.split(",")
    assert len(parts) == 2, f"The file /home/user/ci_output.txt must contain exactly two comma-separated values. Found: {content}"

    try:
        lower = float(parts[0].strip())
        upper = float(parts[1].strip())
    except ValueError:
        assert False, "The values in /home/user/ci_output.txt must be valid numbers."

    assert abs(lower - (-0.2117)) <= 0.0002, f"Expected lower bound approx -0.2117, got {lower}"
    assert abs(upper - 0.1659) <= 0.0002, f"Expected upper bound approx 0.1659, got {upper}"

    canonical = pd.read_csv(DATASET)
    assert content == expected_ci(canonical), (
        "The confidence interval does not match an independently calculated "
        "train-only imputation and scaling pipeline."
    )


def test_pipeline_fixed():
    """Verify that the pipeline script no longer contains the obvious data leakage lines."""
    assert os.path.isfile(PIPELINE), "The file /home/user/pipeline.py does not exist."

    with open(PIPELINE, "r") as f:
        content = f.read()

    assert "imputer.fit_transform(X)" not in content, "The pipeline.py still contains the data leakage: imputer.fit_transform(X)"
    assert "scaler.fit_transform(X_imputed)" not in content, "The pipeline.py still contains the data leakage: scaler.fit_transform(X_imputed)"


def make_adversarial_dataset():
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
    n = 113
    train_idx, test_idx = train_test_split(
        np.arange(n), test_size=0.2, random_state=42
    )
    X = rng.normal(size=(n, 5))
    X[train_idx, 0] = rng.normal(10.0, 2.0, len(train_idx))
    X[test_idx, 0] = rng.normal(80.0, 9.0, len(test_idx))
    X[train_idx[:7], 0] = np.nan
    X[test_idx[:5], 0] = np.nan
    X[train_idx[:4], 2] = np.nan
    X[test_idx[5:9], 2] = np.nan
    df = pd.DataFrame(X, columns=[f"Feature_{i}" for i in range(5)])
    df["Target"] = rng.integers(0, 2, n)
    return df


def test_process_data_uses_train_only_fits():
    df = make_adversarial_dataset()
    temp_path = "/tmp/verifier_dataset.csv"
    df.to_csv(temp_path, index=False)
    disk_df = pd.read_csv(temp_path)
    expected = expected_processing(disk_df)

    spec = importlib.util.spec_from_file_location("submitted_pipeline", PIPELINE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "process_data", None)), (
        "pipeline.py must retain a callable process_data function."
    )
    actual = module.process_data(temp_path)
    assert isinstance(actual, (tuple, list)) and len(actual) == 4, (
        "process_data must return X_train, X_test, y_train, y_test."
    )

    np.testing.assert_allclose(np.asarray(actual[0]), expected[0], rtol=1e-7, atol=1e-8)
    np.testing.assert_allclose(np.asarray(actual[1]), expected[1], rtol=1e-7, atol=1e-8)
    np.testing.assert_array_equal(np.asarray(actual[2]), np.asarray(expected[2]))
    np.testing.assert_array_equal(np.asarray(actual[3]), np.asarray(expected[3]))


def test_executable_pipeline_recomputes_ci_for_changed_data():
    replacement = make_adversarial_dataset()
    expected = expected_ci(replacement)
    with open(DATASET, "rb") as f:
        original_dataset = f.read()
    with open(OUTPUT, "rb") as f:
        original_output = f.read()

    try:
        replacement.to_csv(DATASET, index=False)
        os.remove(OUTPUT)
        run_pipeline()
        assert os.path.isfile(OUTPUT), "pipeline.py did not regenerate ci_output.txt."
        with open(OUTPUT, "r") as f:
            actual = f.read().strip()
        assert actual == expected, (
            f"For a changed dataset, expected CI {expected}, got {actual}. "
            "The pipeline must compute the result rather than hardcode it."
        )
    finally:
        with open(DATASET, "wb") as f:
            f.write(original_dataset)
        with open(OUTPUT, "wb") as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
