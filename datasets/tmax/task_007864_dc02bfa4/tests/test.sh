#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import stat
import subprocess

import numpy as np
import pandas as pd
import pytest

RAW_PATH = "/home/user/data/raw_features.csv"
SCRIPT_PATH = "/home/user/scripts/preprocess.py"
CLEAN_PATH = "/home/user/results/clean_data.csv"
CORR_PATH = "/home/user/results/abs_corr_pca1_target.txt"

EXPECTED_RAW = None
EXPECTED_CATEGORIES = None
EXPECTED_PCA = None


def pearson_corr(x, y):
    n = len(x)
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    num = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    den_x = sum((xi - mean_x) ** 2 for xi in x)
    den_y = sum((yi - mean_y) ** 2 for yi in y)
    if den_x == 0 or den_y == 0:
        return 0.0
    return num / math.sqrt(den_x * den_y)


def reconstruct_original_raw():
    np.random.seed(42)
    n_samples = 100
    data = {
        "id": range(1, n_samples + 1),
        "category": np.random.choice([10, 20, 30, 999], size=n_samples),
        "f1": np.random.randn(n_samples),
        "target": np.random.randint(0, 2, size=n_samples),
    }
    data["f2"] = data["f1"] * 0.5 + np.random.randn(n_samples) * 0.1
    data["f3"] = data["f1"] * -0.3 + np.random.randn(n_samples) * 0.2
    data["f4"] = np.random.randn(n_samples)
    data["f5"] = data["f4"] * 0.8 + np.random.randn(n_samples) * 0.1
    return pd.DataFrame(data)


def compute_expected_pca(raw):
    features = raw[["f1", "f2", "f3", "f4", "f5"]].to_numpy(dtype=float)
    centered = features - features.mean(axis=0)
    cov_matrix = np.cov(centered, rowvar=False)
    eigenvalues, eigenvectors = np.linalg.eigh(cov_matrix)
    sorted_idx = np.argsort(eigenvalues)[::-1]
    eigenvectors = eigenvectors[:, sorted_idx]
    return centered.dot(eigenvectors[:, :2])


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline():
    global EXPECTED_RAW, EXPECTED_CATEGORIES, EXPECTED_PCA

    assert os.path.isfile(RAW_PATH), "raw_features.csv is missing"
    assert os.path.exists(SCRIPT_PATH), "preprocess.py is missing"
    assert stat.S_ISREG(os.lstat(SCRIPT_PATH).st_mode), "preprocess.py must be a regular file"

    # Ensure the input itself was not replaced with data chosen to satisfy the verifier.
    raw = pd.read_csv(RAW_PATH)
    original = reconstruct_original_raw()
    assert list(raw.columns) == list(original.columns), "raw_features.csv schema was modified"
    assert raw.shape == original.shape, "raw_features.csv shape was modified"
    for col in ["id", "category", "target"]:
        assert np.array_equal(raw[col].to_numpy(), original[col].to_numpy()), \
            f"raw_features.csv column {col} was modified"
    for col in ["f1", "f2", "f3", "f4", "f5"]:
        assert np.allclose(raw[col].to_numpy(dtype=float), original[col].to_numpy(dtype=float),
                           rtol=0, atol=1e-14), \
            f"raw_features.csv column {col} was modified"

    EXPECTED_RAW = raw.copy(deep=True)
    EXPECTED_CATEGORIES = raw["category"].replace(999, -1).astype("int64").to_numpy()
    EXPECTED_PCA = compute_expected_pca(raw)

    # Pre-existing fabricated outputs cannot satisfy the task: the submitted artifact
    # must successfully recreate both files during verification.
    for path in [CLEAN_PATH, CORR_PATH]:
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user/scripts",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, \
        f"preprocess.py failed with exit code {result.returncode}:\n{result.stderr}"


def test_clean_data_exists():
    assert os.path.isfile(CLEAN_PATH), "clean_data.csv was not created in /home/user/results/"
    assert stat.S_ISREG(os.lstat(CLEAN_PATH).st_mode), "clean_data.csv must be a regular file"


def test_clean_data_schema_and_pca():
    assert os.path.isfile(CLEAN_PATH), "clean_data.csv is missing"

    categories = []
    pca_1 = []
    pca_2 = []
    targets = []
    ids = []

    with open(CLEAN_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["id", "category", "pca_1", "pca_2", "target"], \
            f"Unexpected output columns: {reader.fieldnames}"
        for row in reader:
            cat_str = row["category"]
            assert cat_str.strip() != "", "Found empty (NaN) value in category column"
            try:
                cat_val = int(cat_str)
            except ValueError:
                pytest.fail(f"Category value '{cat_str}' is not formatted as a strict integer (int64).")

            ids.append(int(row["id"]))
            categories.append(cat_val)
            pca_1.append(float(row["pca_1"]))
            pca_2.append(float(row["pca_2"]))
            targets.append(float(row["target"]))

    assert len(categories) == len(EXPECTED_RAW), "clean_data.csv has the wrong number of rows"
    assert -1 in categories, "-1 was not found in the category column (999 should be replaced with -1)"
    assert 999 not in categories, "999 is still present in the category column"

    # Preserve the strict pandas dtype requirement in addition to integer CSV formatting.
    parsed = pd.read_csv(CLEAN_PATH)
    assert parsed["category"].dtype == np.dtype("int64"), \
        f"category dtype is {parsed['category'].dtype}, expected int64"

    assert np.array_equal(np.asarray(ids), EXPECTED_RAW["id"].to_numpy()), \
        "id values do not match raw_features.csv"
    assert np.array_equal(np.asarray(categories), EXPECTED_CATEGORIES), \
        "category values are not the required transformation of raw_features.csv"
    assert np.array_equal(np.asarray(targets), EXPECTED_RAW["target"].to_numpy(dtype=float)), \
        "target values do not match raw_features.csv"

    actual_pca = np.column_stack([pca_1, pca_2])
    assert np.isfinite(actual_pca).all(), "PCA output contains non-finite values"

    # Eigenvector signs are arbitrary, so accept either sign independently while
    # requiring each component to equal PCA recomputed from the raw features.
    for component in range(2):
        actual = actual_pca[:, component]
        expected = EXPECTED_PCA[:, component]
        sign_independent_error = min(
            np.max(np.abs(actual - expected)),
            np.max(np.abs(actual + expected)),
        )
        assert sign_independent_error < 1e-8, \
            f"pca_{component + 1} does not match centered PCA from raw_features.csv"

    # Original centering and orthogonality assertions.
    n = len(pca_1)
    mean_pca_1 = sum(pca_1) / n
    mean_pca_2 = sum(pca_2) / n
    assert abs(mean_pca_1) < 1e-5, \
        f"pca_1 is not mean-centered (mean = {mean_pca_1}). Did you subtract the mean before projection?"
    assert abs(mean_pca_2) < 1e-5, \
        f"pca_2 is not mean-centered (mean = {mean_pca_2}). Did you subtract the mean before projection?"

    dot_product = sum(p1 * p2 for p1, p2 in zip(pca_1, pca_2))
    assert abs(dot_product) < 1e-4, \
        f"pca_1 and pca_2 are not orthogonal (dot product = {dot_product}). PCA implementation is incorrect."


def test_correlation_output():
    assert os.path.isfile(CORR_PATH), "abs_corr_pca1_target.txt was not created"
    assert stat.S_ISREG(os.lstat(CORR_PATH).st_mode), \
        "abs_corr_pca1_target.txt must be a regular file"

    with open(CORR_PATH, "r") as f:
        content = f.read().strip()
        try:
            reported_corr = float(content)
        except ValueError:
            pytest.fail(f"Content of abs_corr_pca1_target.txt is not a valid float: {content}")
    assert math.isfinite(reported_corr), "Reported correlation must be finite"

    # Preserve the original consistency check against the generated CSV.
    pca_1 = []
    targets = []
    with open(CLEAN_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            pca_1.append(float(row["pca_1"]))
            targets.append(float(row["target"]))

    actual_corr = abs(pearson_corr(pca_1, targets))
    expected_corr_rounded = round(actual_corr, 4)
    assert abs(reported_corr - expected_corr_rounded) < 1e-4, \
        f"Correlation value mismatch. Expected {expected_corr_rounded}, got {reported_corr}"

    # Also derive the expected value from the trusted raw data and correct PCA.
    correct_corr = abs(pearson_corr(
        EXPECTED_PCA[:, 0].tolist(),
        EXPECTED_RAW["target"].astype(float).tolist(),
    ))
    correct_rounded = round(correct_corr, 4)
    assert abs(reported_corr - correct_rounded) < 1e-4, \
        f"Correlation is not based on correct PCA. Expected {correct_rounded}, got {reported_corr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
