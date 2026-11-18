#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os

import numpy as np
import pandas as pd
import pytest
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler

PROCESSED_DIR = "/home/user/data/processed"
RAW_DIR = "/home/user/data/raw"
PCA_CSV_PATH = os.path.join(PROCESSED_DIR, "pca_features.csv")
VAR_TXT_PATH = os.path.join(PROCESSED_DIR, "explained_variance.txt")


def test_processed_files_exist():
    """Test that the required output files exist."""
    assert os.path.exists(PCA_CSV_PATH), f"Failure: {PCA_CSV_PATH} missing"
    assert os.path.isfile(PCA_CSV_PATH), f"Failure: {PCA_CSV_PATH} is not a file"

    assert os.path.exists(VAR_TXT_PATH), f"Failure: {VAR_TXT_PATH} missing"
    assert os.path.isfile(VAR_TXT_PATH), f"Failure: {VAR_TXT_PATH} is not a file"


def test_pca_features_csv_format():
    """Test that the pca_features.csv has the correct headers and row count."""
    with open(PCA_CSV_PATH, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == 298, f"Failure: Expected 298 lines in pca_features.csv, got {len(lines)}"

    expected_header = "timestamp,machine_id,PC1,PC2,PC3"
    assert lines[0] == expected_header, f"Failure: Incorrect headers in pca_features.csv. Expected '{expected_header}', got '{lines[0]}'"

    for i, line in enumerate(lines[1:], start=2):
        cols = line.split(",")
        assert len(cols) == 5, f"Failure: Row {i} in pca_features.csv does not have 5 columns."


def test_explained_variance_txt_format():
    """Test that the explained_variance.txt has exactly three comma-separated float values."""
    with open(VAR_TXT_PATH, "r") as f:
        content = f.read().strip()

    values = content.split(",")
    assert len(values) == 3, f"Failure: Expected 3 comma-separated values in explained_variance.txt, got {len(values)}"

    for val in values:
        try:
            float(val)
        except ValueError:
            pytest.fail(f"Failure: Value '{val}' in explained_variance.txt is not a valid float.")


def compute_expected_results():
    raw_paths = sorted(glob.glob(os.path.join(RAW_DIR, "*.csv")))
    assert raw_paths, f"Failure: No raw CSV files found in {RAW_DIR}"

    raw = pd.concat([pd.read_csv(path) for path in raw_paths], ignore_index=True)
    sensor_columns = [f"sensor_{i}" for i in range(1, 21)]
    required_columns = ["timestamp", "machine_id"] + sensor_columns
    assert all(column in raw.columns for column in required_columns), "Failure: Raw data is missing required columns"

    filtered = raw.dropna(axis=0, how="any")
    filtered = filtered.loc[filtered["sensor_1"] >= 0].copy()

    scaled = StandardScaler().fit_transform(filtered[sensor_columns])
    model = PCA(n_components=3, random_state=42)
    components = model.fit_transform(scaled)

    expected = filtered[["timestamp", "machine_id"]].copy()
    expected[["PC1", "PC2", "PC3"]] = components
    expected["timestamp"] = expected["timestamp"].astype(str)
    expected["machine_id"] = expected["machine_id"].astype(str)
    return expected, model.explained_variance_ratio_


def test_outputs_match_etl_and_pca_pipeline():
    """Recompute the requested pipeline and compare all submitted values."""
    expected, expected_variance = compute_expected_results()
    actual = pd.read_csv(
        PCA_CSV_PATH,
        dtype={"timestamp": str, "machine_id": str},
    )

    assert list(actual.columns) == ["timestamp", "machine_id", "PC1", "PC2", "PC3"]
    assert len(actual) == len(expected), "Failure: Output row count does not match the filtered raw data"

    keys = ["timestamp", "machine_id"]
    assert not expected.duplicated(keys).any(), "Failure: Verification data has duplicate row identifiers"
    assert not actual.duplicated(keys).any(), "Failure: Output contains duplicate timestamp/machine_id rows"

    expected_indexed = expected.set_index(keys)
    actual_indexed = actual.set_index(keys)
    assert set(actual_indexed.index) == set(expected_indexed.index), \
        "Failure: Output timestamps or machine IDs do not match the filtered raw data"
    actual_indexed = actual_indexed.reindex(expected_indexed.index)

    component_columns = ["PC1", "PC2", "PC3"]
    try:
        actual_components = actual_indexed[component_columns].to_numpy(dtype=float)
    except (TypeError, ValueError):
        pytest.fail("Failure: PCA component columns must contain numeric values")

    expected_components = expected_indexed[component_columns].to_numpy(dtype=float)
    assert np.isfinite(actual_components).all(), "Failure: PCA output contains non-finite values"
    np.testing.assert_allclose(
        actual_components,
        expected_components,
        rtol=1e-7,
        atol=1e-8,
        err_msg="Failure: PCA component values do not match the requested pipeline",
    )

    with open(VAR_TXT_PATH, "r") as f:
        actual_variance = np.array([float(value) for value in f.read().strip().split(",")])
    assert np.isfinite(actual_variance).all(), "Failure: Explained variance contains non-finite values"
    np.testing.assert_allclose(
        actual_variance,
        expected_variance,
        rtol=1e-7,
        atol=1e-9,
        err_msg="Failure: Explained variance ratios do not match the fitted PCA model",
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
