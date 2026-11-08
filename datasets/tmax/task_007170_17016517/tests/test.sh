#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os

import numpy as np
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler

PREDICTIONS = "/home/user/predictions.csv"
BENCHMARK = "/home/user/benchmark.txt"
DATASET = "/home/user/sensor_data.csv"


def test_predictions_csv_exists():
    assert os.path.exists(PREDICTIONS), f"{PREDICTIONS} was not found."
    assert os.path.isfile(PREDICTIONS), f"{PREDICTIONS} is not a file."


def test_benchmark_txt_exists():
    assert os.path.exists(BENCHMARK), f"{BENCHMARK} was not found."
    assert os.path.isfile(BENCHMARK), f"{BENCHMARK} is not a file."


def test_predictions_csv_content_and_pipeline_results():
    with open(PREDICTIONS, "r", newline="") as f:
        rows = list(csv.reader(f))

    assert len(rows) > 1, "predictions.csv does not contain any data rows."

    expected_header = ["machine_id", "pc1", "pc2", "pc3", "prediction"]
    assert rows[0] == expected_header, (
        f"Columns mismatch. Expected {expected_header}, got {rows[0]}."
    )

    source = pd.read_csv(DATASET)
    data_rows = rows[1:]
    assert len(data_rows) == len(source), (
        f"Expected exactly {len(source)} prediction rows, got {len(data_rows)}."
    )
    for i, row in enumerate(data_rows):
        assert len(row) == 5, f"Row {i} has {len(row)} columns instead of 5."
        assert "." not in row[0], (
            f"machine_id at row {i} contains decimals: '{row[0]}'. "
            "It was not properly cast to int."
        )

    expected_ids = source["machine_id"].fillna(999).astype(int).astype(str).tolist()
    actual_ids = [row[0] for row in data_rows]
    assert actual_ids == expected_ids, "machine_id values or row ordering are incorrect."
    assert data_rows[150][0] == "999", (
        "Missing value at row 150 was not correctly imputed with 999. "
        f"Found '{data_rows[150][0]}'."
    )

    try:
        actual_pcs = np.asarray(
            [[float(row[1]), float(row[2]), float(row[3])] for row in data_rows],
            dtype=float,
        )
        actual_predictions = np.asarray([float(row[4]) for row in data_rows])
    except ValueError as exc:
        raise AssertionError(f"PCA values and predictions must be numeric: {exc}")

    assert np.isfinite(actual_pcs).all(), "PCA output contains NaN or infinity."
    assert np.isfinite(actual_predictions).all(), "Predictions contain NaN or infinity."

    sensor_columns = [f"sensor_{i}" for i in range(1, 11)]
    features = source[sensor_columns]
    scaled = StandardScaler().fit_transform(features)
    expected_pcs = PCA(n_components=3).fit_transform(scaled)
    expected_predictions = LogisticRegression().fit(
        expected_pcs, source["is_faulty"]
    ).predict(expected_pcs)

    # Principal-component signs are mathematically arbitrary, so accept an
    # independent sign reversal for each component.
    for component in range(3):
        actual = actual_pcs[:, component]
        expected = expected_pcs[:, component]
        matches = np.allclose(actual, expected, rtol=1e-5, atol=1e-5)
        matches_reversed = np.allclose(actual, -expected, rtol=1e-5, atol=1e-5)
        assert matches or matches_reversed, (
            f"pc{component + 1} does not match standardized three-component PCA."
        )

    assert np.all(actual_predictions == np.floor(actual_predictions)), (
        "Predictions must be integer class labels."
    )
    assert np.array_equal(actual_predictions.astype(int), expected_predictions), (
        "Predictions do not match default Logistic Regression trained on the PCA output."
    )


def test_benchmark_txt_content():
    with open(BENCHMARK, "r") as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        raise AssertionError(
            f"benchmark.txt does not contain a valid float. Found: '{content}'"
        )

    assert val >= 0, f"Benchmark value must be positive, got {val}."
    assert math.isfinite(val), f"Benchmark value must be finite, got {val}."
    assert val > 0, f"Average inference time must be positive, got {val}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
