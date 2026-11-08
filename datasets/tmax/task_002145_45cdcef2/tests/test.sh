#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math

import numpy as np
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.feature_extraction.text import TfidfVectorizer

PARQUET_PATH = "/home/user/processed_data.parquet"
JSON_PATH = "/home/user/experiment_log.json"
CSV_PATH = "/home/user/raw_dataset.csv"


def test_experiment_log_and_parquet_exist():
    assert os.path.isfile(PARQUET_PATH), f"Parquet file {PARQUET_PATH} was not created."
    assert os.path.getsize(PARQUET_PATH) > 0, f"Parquet file {PARQUET_PATH} is empty."

    assert os.path.isfile(JSON_PATH), f"JSON log file {JSON_PATH} was not created."
    assert os.path.getsize(JSON_PATH) > 0, f"JSON log file {JSON_PATH} is empty."


def compute_expected_results():
    raw = pd.read_csv(CSV_PATH)
    cleaned = raw.loc[raw["text"].notna() & (raw["text"] != "")].copy()

    numeric_ages = pd.to_numeric(cleaned["author_age"], errors="coerce")
    valid_ages = numeric_ages[numeric_ages.between(15, 100, inclusive="both")]
    assert len(valid_ages) > 0, "No valid ages found to compute median."
    expected_median = float(valid_ages.median())

    vectorizer = TfidfVectorizer(max_features=50, lowercase=True)
    tfidf = vectorizer.fit_transform(cleaned["text"])
    pca = PCA(n_components=2, random_state=42)
    components = pca.fit_transform(tfidf.toarray())

    return raw, cleaned, expected_median, components, float(round(pca.explained_variance_ratio_.sum(), 4))


def test_experiment_log_contents():
    # Preserve the original independent CSV-based checks.
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    initial_rows = len(rows)
    valid_ages = []
    cleaned_rows = 0
    for row in rows:
        text = row.get("text", "")
        if text is None or text == "":
            continue
        cleaned_rows += 1
        try:
            age = float(row.get("author_age", ""))
            if 15 <= age <= 100:
                valid_ages.append(age)
        except ValueError:
            pass

    valid_ages.sort()
    n = len(valid_ages)
    assert n > 0, "No valid ages found to compute median."
    if n % 2 == 1:
        expected_median = float(valid_ages[n // 2])
    else:
        expected_median = (valid_ages[n // 2 - 1] + valid_ages[n // 2]) / 2.0

    with open(JSON_PATH, "r", encoding="utf-8") as f:
        try:
            log = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {JSON_PATH} is not valid JSON."

    expected_keys = {"initial_rows", "cleaned_rows", "median_age_used", "explained_variance_ratio_sum"}
    assert set(log.keys()) == expected_keys, f"JSON keys mismatch. Expected {expected_keys}, got {set(log.keys())}"
    assert log["initial_rows"] == initial_rows, f"Expected initial_rows={initial_rows}, got {log['initial_rows']}"
    assert log["cleaned_rows"] == cleaned_rows, f"Expected cleaned_rows={cleaned_rows}, got {log['cleaned_rows']}"
    assert math.isclose(float(log["median_age_used"]), expected_median, abs_tol=1e-5), \
        f"Expected median_age_used={expected_median}, got {log['median_age_used']}"

    evr_sum = log["explained_variance_ratio_sum"]
    assert isinstance(evr_sum, float), f"explained_variance_ratio_sum must be a float, got {type(evr_sum)}"
    assert 0.05 < evr_sum < 0.15, \
        f"explained_variance_ratio_sum {evr_sum} is outside the expected plausible range (0.05 - 0.15)."

    _, _, _, _, expected_evr = compute_expected_results()
    assert evr_sum == expected_evr, \
        f"Expected explained_variance_ratio_sum={expected_evr}, got {evr_sum}"


def test_processed_parquet_contents():
    _, cleaned, _, expected_components, _ = compute_expected_results()

    try:
        processed = pd.read_parquet(PARQUET_PATH)
    except Exception as exc:
        assert False, f"File {PARQUET_PATH} is not a readable Parquet file: {exc}"

    assert list(processed.columns) == ["id", "pca_1", "pca_2"], \
        f"Parquet columns must be exactly ['id', 'pca_1', 'pca_2'] in that order; got {list(processed.columns)}"
    assert len(processed) == len(cleaned), \
        f"Expected {len(cleaned)} Parquet rows, got {len(processed)}"
    assert processed["id"].tolist() == cleaned["id"].tolist(), \
        "Parquet id values or row order do not match the cleaned dataset."

    for column in ["pca_1", "pca_2"]:
        assert pd.api.types.is_numeric_dtype(processed[column]), f"{column} must be numeric."
    actual_components = processed[["pca_1", "pca_2"]].to_numpy(dtype=float)
    assert np.isfinite(actual_components).all(), "PCA columns contain NaN or infinite values."
    np.testing.assert_allclose(
        actual_components,
        expected_components,
        rtol=1e-6,
        atol=1e-8,
        err_msg="Parquet PCA values do not match TF-IDF followed by the required PCA.",
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
