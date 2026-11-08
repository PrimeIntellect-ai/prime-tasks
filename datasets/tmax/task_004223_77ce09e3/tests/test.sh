#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math

import pandas as pd
from scipy.stats import ttest_rel
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler


def test_report_json_exists_and_valid():
    report_path = '/home/user/report.json'
    assert os.path.isfile(report_path), f"Expected report file at {report_path} is missing."

    with open(report_path, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {report_path} does not contain valid JSON."

    expected_keys = {"leaky_mse", "fixed_mse", "p_value"}
    actual_keys = set(report_data.keys())
    assert actual_keys == expected_keys, f"JSON keys in {report_path} do not match expected. Expected: {expected_keys}, Got: {actual_keys}"

    for key in expected_keys:
        val = report_data[key]
        assert isinstance(val, (int, float)), f"Expected numeric value for {key}, got {type(val).__name__}."
        assert not math.isnan(val), f"Value for {key} is NaN."


def test_report_json_values_plausible():
    report_path = '/home/user/report.json'
    if not os.path.isfile(report_path):
        return # Handled by previous test

    with open(report_path, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            return

    if not set(report_data.keys()) == {"leaky_mse", "fixed_mse", "p_value"}:
        return

    leaky_mse = report_data["leaky_mse"]
    fixed_mse = report_data["fixed_mse"]
    p_value = report_data["p_value"]

    assert leaky_mse > 0, f"leaky_mse must be strictly positive, got {leaky_mse}"
    assert fixed_mse > 0, f"fixed_mse must be strictly positive, got {fixed_mse}"
    assert 0.0 <= p_value <= 1.0, f"p_value must be a valid probability between 0 and 1, got {p_value}"


def compute_expected_results():
    with open('/home/user/schema.json', 'r') as f:
        schema = json.load(f)

    schema_columns = list(schema['columns'].keys())
    assert 'target' in schema_columns, "Schema must define the target column."

    df = pd.read_csv('/home/user/data.csv')
    missing = [column for column in schema_columns if column not in df.columns]
    assert not missing, f"CSV is missing schema columns: {missing}"

    # Restrict modeling to the schema columns and discard all extras.
    df = df.loc[:, schema_columns]
    feature_columns = [column for column in schema_columns if column != 'target']
    X = df.loc[:, feature_columns]
    y = df['target']

    # Reconstruct the leaky pipeline: fit scaling globally before splitting.
    leaky_scaler = StandardScaler()
    X_leaky = leaky_scaler.fit_transform(X)
    X_train_leaky, X_test_leaky, y_train, y_test = train_test_split(
        X_leaky, y, test_size=0.2, random_state=42
    )
    leaky_model = Ridge(alpha=1.0)
    leaky_model.fit(X_train_leaky, y_train)
    leaky_predictions = leaky_model.predict(X_test_leaky)

    # Correct pipeline: split first, then fit the scaler only on training data.
    X_train, X_test, y_train_fixed, y_test_fixed = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    fixed_scaler = StandardScaler()
    X_train_fixed = fixed_scaler.fit_transform(X_train)
    X_test_fixed = fixed_scaler.transform(X_test)
    fixed_model = Ridge(alpha=1.0)
    fixed_model.fit(X_train_fixed, y_train_fixed)
    fixed_predictions = fixed_model.predict(X_test_fixed)

    leaky_errors = abs(y_test.to_numpy() - leaky_predictions)
    fixed_errors = abs(y_test_fixed.to_numpy() - fixed_predictions)
    p_value = ttest_rel(leaky_errors, fixed_errors, alternative='two-sided').pvalue

    return {
        'leaky_mse': mean_squared_error(y_test, leaky_predictions),
        'fixed_mse': mean_squared_error(y_test_fixed, fixed_predictions),
        'p_value': p_value,
    }


def test_report_matches_recomputed_pipelines():
    with open('/home/user/report.json', 'r') as f:
        report_data = json.load(f)

    expected = compute_expected_results()
    for key, expected_value in expected.items():
        actual_value = report_data[key]
        assert math.isfinite(actual_value), f"{key} must be finite, got {actual_value}"
        assert math.isclose(actual_value, expected_value, rel_tol=1e-10, abs_tol=1e-12), (
            f"Incorrect {key}: expected {expected_value!r}, got {actual_value!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
