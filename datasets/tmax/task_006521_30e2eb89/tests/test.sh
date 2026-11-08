#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
from decimal import Decimal

import numpy as np
import pandas as pd
from sklearn.ensemble import IsolationForest
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.decomposition import TruncatedSVD


def test_results_csv_exists():
    """Test that the results.csv file exists in the correct directory."""
    file_path = "/home/user/results.csv"
    assert os.path.exists(file_path), f"Missing file: {file_path}"
    assert os.path.isfile(file_path), f"Not a file: {file_path}"


def test_results_csv_columns():
    """Test that results.csv has the exact expected columns."""
    file_path = "/home/user/results.csv"
    with open(file_path, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        expected_cols = ['original_message', 'svd_1', 'svd_2', 'is_anomaly']
        assert header == expected_cols, f"Expected columns {expected_cols}, got {header}"


def test_results_csv_content():
    """Test that results.csv is correctly formatted, sorted, and has the right anomaly count."""
    file_path = "/home/user/results.csv"
    with open(file_path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert len(rows) == 50, f"Expected 50 rows of data, got {len(rows)}"

    # Check that original_message is sorted alphabetically
    messages = [row['original_message'] for row in rows]
    assert messages == sorted(messages), "Error: DataFrame is not sorted alphabetically by original_message."

    # Check is_anomaly values and count
    anomalies_count = 0
    for i, row in enumerate(rows):
        val = row['is_anomaly']
        assert val in ('0', '1'), f"Row {i+1}: is_anomaly column must contain only 0 and 1, got {val}"
        anomalies_count += int(val)

    assert anomalies_count == 5, f"Error: Expected exactly 5 anomalies (10% of 50), found {anomalies_count}"


def test_results_match_required_pipeline():
    input_path = "/home/user/data/logs.csv"
    input_df = pd.read_csv(input_path, dtype=str, keep_default_na=False)
    assert list(input_df.columns) == ["message"], "Input CSV must contain the message column"

    original_messages = input_df["message"].tolist()
    cleaned = input_df["message"].str.lower().str.replace(r"[^a-z0-9 ]", "", regex=True)

    tfidf = TfidfVectorizer(stop_words="english").fit_transform(cleaned)
    features = TruncatedSVD(n_components=2, random_state=42).fit_transform(tfidf)
    predictions = IsolationForest(contamination=0.1, random_state=42).fit_predict(features)

    expected = pd.DataFrame({
        "original_message": original_messages,
        "svd_1": np.round(features[:, 0], 4),
        "svd_2": np.round(features[:, 1], 4),
        "is_anomaly": (predictions == -1).astype(int),
    }).sort_values("original_message", kind="mergesort").reset_index(drop=True)

    with open("/home/user/results.csv", "r", encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))

    actual_messages = [row["original_message"] for row in rows]
    assert actual_messages == expected["original_message"].tolist(), \
        "original_message values do not match the sorted input messages"

    actual_components = np.empty((len(rows), 2), dtype=float)
    for i, row in enumerate(rows):
        for j, name in enumerate(("svd_1", "svd_2")):
            raw = row[name]
            try:
                value = float(raw)
                decimal_value = Decimal(raw)
            except Exception as exc:
                raise AssertionError(f"Row {i+1}: {name} is not numeric: {raw!r}") from exc
            assert math.isfinite(value), f"Row {i+1}: {name} must be finite"
            assert decimal_value == decimal_value.quantize(Decimal("0.0001")), \
                f"Row {i+1}: {name} is not rounded to at most 4 decimal places"
            actual_components[i, j] = value

    # Singular vectors may validly be reported with either global sign.
    for j, name in enumerate(("svd_1", "svd_2")):
        expected_values = expected[name].to_numpy(dtype=float)
        actual_values = actual_components[:, j]
        matches_positive = np.allclose(actual_values, expected_values, rtol=0, atol=5e-5)
        matches_negative = np.allclose(actual_values, -expected_values, rtol=0, atol=5e-5)
        assert matches_positive or matches_negative, \
            f"{name} values do not match the required TF-IDF and TruncatedSVD pipeline"

    actual_flags = np.array([int(row["is_anomaly"]) for row in rows], dtype=int)
    expected_flags = expected["is_anomaly"].to_numpy(dtype=int)
    assert np.array_equal(actual_flags, expected_flags), \
        "is_anomaly flags do not match IsolationForest(contamination=0.1, random_state=42)"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
