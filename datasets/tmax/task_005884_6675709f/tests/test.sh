#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import Ridge
from sklearn.model_selection import KFold, cross_val_score

REPORT_PATH = "/home/user/report.json"
CLEANED_CSV_PATH = "/home/user/cleaned_sensors.csv"
RAW_PATH = "/home/user/data/sensors_raw.csv"
ALPHAS = [0.1, 1.0, 10.0]


def load_report():
    assert os.path.isfile(REPORT_PATH), f"Report file missing at {REPORT_PATH}"
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("report.json is not a valid JSON file.")


def expected_results():
    raw = pd.read_csv(RAW_PATH)
    sensor_columns = [c for c in raw.columns if c != "target_temp"]

    dropped = []
    correlations = raw[sensor_columns].corr(method="pearson")
    for later_idx in range(1, len(sensor_columns)):
        later = sensor_columns[later_idx]
        for earlier_idx in range(later_idx):
            earlier = sensor_columns[earlier_idx]
            if correlations.loc[earlier, later] > 0.95:
                dropped.append(later)
                break

    assert dropped == ["sensor_B"], f"Unexpected correlation structure in raw data: {dropped}"
    dropped_column = dropped[0]

    values_d = raw["sensor_D"].to_numpy(dtype=float)
    rng = np.random.RandomState(42)
    bootstrap_sum = 0.0
    completed = 0
    while completed < 10000:
        batch = min(250, 10000 - completed)
        indices = rng.randint(0, len(values_d), size=(batch, len(values_d)))
        bootstrap_sum += values_d[indices].sum(dtype=np.float64)
        completed += batch
    bootstrap_mean = round(bootstrap_sum / (10000 * len(values_d)), 2)

    feature_columns = [
        c for c in sensor_columns
        if c not in set(dropped) and c != "sensor_D"
    ]
    observed = raw["target_temp"].notna()
    x_train = raw.loc[observed, feature_columns]
    y_train = raw.loc[observed, "target_temp"]

    cv = KFold(n_splits=5, shuffle=True, random_state=42)
    mean_scores = {}
    for alpha in ALPHAS:
        scores = cross_val_score(
            Ridge(alpha=alpha), x_train, y_train,
            cv=cv, scoring="neg_mean_squared_error"
        )
        mean_scores[alpha] = float(scores.mean())
    best_alpha = max(ALPHAS, key=lambda alpha: mean_scores[alpha])

    model = Ridge(alpha=best_alpha)
    model.fit(x_train, y_train)
    expected_targets = raw["target_temp"].copy()
    missing = ~observed
    expected_targets.loc[missing] = model.predict(raw.loc[missing, feature_columns])

    return raw, dropped_column, bootstrap_mean, best_alpha, expected_targets


def test_report_exists_and_valid():
    """Retain the original report checks and validate the recomputed results."""
    report = load_report()

    assert "dropped_column" in report, "Key 'dropped_column' missing in report."
    assert report["dropped_column"] == "sensor_B", f"Expected dropped_column to be 'sensor_B', got {report['dropped_column']}"

    assert "bootstrap_mean_sensor_D" in report, "Key 'bootstrap_mean_sensor_D' missing in report."
    mean_d = report["bootstrap_mean_sensor_D"]
    assert isinstance(mean_d, (int, float)), "bootstrap_mean_sensor_D must be a number."
    assert 99.0 <= mean_d <= 101.0, f"Bootstrap mean {mean_d} is out of expected bounds (99.0 - 101.0)."

    assert "best_ridge_alpha" in report, "Key 'best_ridge_alpha' missing in report."
    alpha = report["best_ridge_alpha"]
    assert alpha in ALPHAS, f"best_ridge_alpha {alpha} is not in the allowed grid [0.1, 1.0, 10.0]."

    _, expected_drop, expected_bootstrap, expected_alpha, _ = expected_results()
    assert set(report.keys()) == {
        "dropped_column", "bootstrap_mean_sensor_D", "best_ridge_alpha"
    }, "report.json must contain exactly the three requested keys."
    assert report["dropped_column"] == expected_drop
    assert np.isfinite(float(mean_d)), "bootstrap_mean_sensor_D must be finite."
    assert float(mean_d) == expected_bootstrap, (
        f"Expected bootstrap mean {expected_bootstrap}, got {mean_d}"
    )
    assert float(alpha) == expected_alpha, (
        f"Expected best Ridge alpha {expected_alpha}, got {alpha}"
    )


def test_cleaned_dataset_exists_and_valid():
    """Retain the original CSV checks and compare the full result to the raw data."""
    assert os.path.isfile(CLEANED_CSV_PATH), f"Cleaned dataset missing at {CLEANED_CSV_PATH}"

    with open(CLEANED_CSV_PATH, "r") as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail("Cleaned dataset is empty.")

        assert "sensor_B" not in headers, "sensor_B was not removed from the final CSV."
        assert "target_temp" in headers, "target_temp column missing in the final CSV."
        target_idx = headers.index("target_temp")

        for row_num, row in enumerate(reader, start=2):
            if not row:
                continue
            assert len(row) > target_idx, f"Row {row_num} is malformed."
            val = row[target_idx].strip()
            assert val != "", f"Missing value found in target_temp at row {row_num}."
            assert val.lower() not in ["nan", "null", "na"], f"Unimputed missing value '{val}' found in target_temp at row {row_num}."

    raw, dropped, _, _, expected_targets = expected_results()
    cleaned = pd.read_csv(CLEANED_CSV_PATH)
    expected_columns = [c for c in raw.columns if c != dropped]

    assert list(cleaned.columns) == expected_columns, (
        f"Expected columns in original order {expected_columns}, got {list(cleaned.columns)}"
    )
    assert len(cleaned) == len(raw), (
        f"Expected {len(raw)} rows, got {len(cleaned)}"
    )

    for column in expected_columns:
        if column == "target_temp":
            continue
        np.testing.assert_allclose(
            cleaned[column].to_numpy(dtype=float),
            raw[column].to_numpy(dtype=float),
            rtol=1e-12,
            atol=1e-12,
            equal_nan=True,
            err_msg=f"Column {column} or its row order was changed",
        )

    actual_targets = cleaned["target_temp"].to_numpy(dtype=float)
    assert np.isfinite(actual_targets).all(), "target_temp still contains non-finite values."
    np.testing.assert_allclose(
        actual_targets,
        expected_targets.to_numpy(dtype=float),
        rtol=1e-8,
        atol=1e-8,
        err_msg="target_temp does not contain the expected Ridge imputations",
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
