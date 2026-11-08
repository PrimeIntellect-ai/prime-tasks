#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from collections import Counter

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import GridSearchCV
from sklearn.naive_bayes import GaussianNB


def test_summary_json_exists_and_valid():
    """Test that summary.json exists, contains the correct keys, and values have expected types/bounds."""
    file_path = "/home/user/summary.json"
    assert os.path.exists(file_path), f"Missing file: {file_path} does not exist."

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    assert "avg_posterior_class1" in data, "Missing key 'avg_posterior_class1' in summary.json."
    assert "best_c_mode" in data, "Missing key 'best_c_mode' in summary.json."

    avg_post = data["avg_posterior_class1"]
    best_c = data["best_c_mode"]

    assert isinstance(avg_post, (int, float)), "'avg_posterior_class1' must be a number."
    assert 0.0 <= avg_post <= 1.0, "'avg_posterior_class1' must be a probability between 0 and 1."

    assert isinstance(best_c, (int, float)), "'best_c_mode' must be a number."
    assert best_c in [0.01, 0.1, 1.0, 10.0], f"'best_c_mode' must be one of the grid values [0.01, 0.1, 1.0, 10.0], got {best_c}."


def _canonical_input():
    np.random.seed(123)
    n_samples = 1000
    y_true = np.random.binomial(1, 0.5, n_samples)
    sensor_1 = np.where(
        y_true == 1,
        np.random.normal(1.5, 1.0, n_samples),
        np.random.normal(-0.5, 1.0, n_samples),
    )
    sensor_2 = np.where(
        y_true == 1,
        np.random.normal(-1.0, 1.5, n_samples),
        np.random.normal(1.0, 1.5, n_samples),
    )
    sensor_3 = np.random.normal(0, 2.0, n_samples)
    expected = pd.DataFrame({
        "sensor_1": sensor_1,
        "sensor_2": sensor_2,
        "sensor_3": sensor_3,
        "target": y_true.astype(float),
    })
    missing_idx = np.random.choice(n_samples, size=int(n_samples * 0.3), replace=False)
    expected.loc[missing_idx, "target"] = np.nan
    return expected


def test_summary_matches_required_computation():
    data_path = "/home/user/sensor_data.csv"
    assert os.path.isfile(data_path), f"Missing input dataset: {data_path}"

    df = pd.read_csv(data_path)
    assert list(df.columns) == ["sensor_1", "sensor_2", "sensor_3", "target"]

    # Ensure the task input was not replaced with an easier dataset after setup.
    canonical = _canonical_input()
    assert df.shape == canonical.shape
    for column in canonical.columns:
        np.testing.assert_allclose(
            df[column].to_numpy(),
            canonical[column].to_numpy(),
            rtol=1e-12,
            atol=1e-12,
            equal_nan=True,
            err_msg=f"The input column {column!r} was modified",
        )

    features = ["sensor_1", "sensor_2", "sensor_3"]
    labeled_mask = df["target"].notna()
    unlabeled_mask = ~labeled_mask

    gnb = GaussianNB()
    gnb.fit(df.loc[labeled_mask, features], df.loc[labeled_mask, "target"])
    class_one_index = int(np.flatnonzero(gnb.classes_ == 1)[0])
    probabilities = gnb.predict_proba(df.loc[unlabeled_mask, features])[:, class_one_index]
    expected_avg = round(float(np.mean(probabilities)), 4)

    rng = np.random.default_rng(42)
    selected_cs = []
    for _ in range(50):
        completed_targets = df["target"].copy()
        draws = rng.random(size=int(unlabeled_mask.sum()))
        completed_targets.loc[unlabeled_mask] = (draws < probabilities).astype(int)

        search = GridSearchCV(
            LogisticRegression(max_iter=1000, random_state=42),
            param_grid={"C": [0.01, 0.1, 1.0, 10.0]},
            scoring="accuracy",
            cv=3,
        )
        search.fit(df[features], completed_targets.astype(int))
        selected_cs.append(float(search.best_params_["C"]))

    counts = Counter(selected_cs)
    highest_count = max(counts.values())
    expected_mode = min(c for c, count in counts.items() if count == highest_count)

    with open("/home/user/summary.json", "r") as f:
        result = json.load(f)

    assert set(result) == {"avg_posterior_class1", "best_c_mode"}, \
        "summary.json must contain exactly the two requested keys."
    assert float(result["avg_posterior_class1"]) == expected_avg, \
        f"Incorrect average posterior: expected {expected_avg}, got {result['avg_posterior_class1']}"
    assert float(result["best_c_mode"]) == expected_mode, \
        f"Incorrect best C mode: expected {expected_mode}, got {result['best_c_mode']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
