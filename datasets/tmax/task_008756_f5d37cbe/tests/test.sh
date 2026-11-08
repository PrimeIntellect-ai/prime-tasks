#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import statistics
import pytest
import pandas as pd
from sklearn.linear_model import BayesianRidge
from sklearn.model_selection import GridSearchCV
from sklearn.metrics import mean_squared_error


def get_pearson_corr(x, y):
    n = len(x)
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    num = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    den_x = sum((xi - mean_x) ** 2 for xi in x)
    den_y = sum((yi - mean_y) ** 2 for yi in y)
    if den_x == 0 or den_y == 0:
        return 0.0
    return num / math.sqrt(den_x * den_y)


def test_pipeline_results_json():
    json_path = "/home/user/pipeline_results.json"
    csv_path = "/home/user/data/sensor_log.csv"

    assert os.path.exists(json_path), f"The result file is missing: {json_path}"

    with open(json_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_path} does not contain valid JSON.")

    assert "dropped_columns" in results, "Missing 'dropped_columns' in JSON."
    assert "best_params" in results, "Missing 'best_params' in JSON."
    assert "mse" in results, "Missing 'mse' in JSON."

    # Compute expected dropped columns using stdlib.
    assert os.path.exists(csv_path), f"The dataset file is missing: {csv_path}"

    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        data = {field: [] for field in reader.fieldnames}
        for row in reader:
            for field in reader.fieldnames:
                data[field].append(row[field])

    event_counts = [float(v) for v in data["event_count"] if v.strip() != ""]
    median_ec = statistics.median(event_counts)

    imputed_ec = []
    for v in data["event_count"]:
        if v.strip() == "":
            imputed_ec.append(int(median_ec))
        else:
            imputed_ec.append(int(float(v)))
    data["event_count"] = imputed_ec

    for field in ["sensor_1", "sensor_2", "sensor_3"]:
        data[field] = [float(v) for v in data[field]]

    features = [f for f in data.keys() if f != "system_load"]
    expected_dropped = []
    s1 = data["sensor_1"]
    for feature in features:
        if feature == "sensor_1":
            continue
        corr = abs(get_pearson_corr(s1, data[feature]))
        if corr > 0.80:
            expected_dropped.append(feature)
    expected_dropped.sort()

    assert results["dropped_columns"] == expected_dropped, \
        f"Expected dropped_columns to be {expected_dropped}, but got {results['dropped_columns']}."

    # Preserve the original structure and grid-membership checks.
    expected_params_keys = {"alpha_1", "alpha_2", "lambda_1", "lambda_2"}
    assert set(results["best_params"].keys()) == expected_params_keys, \
        f"Expected best_params keys to be {expected_params_keys}, but got {set(results['best_params'].keys())}."

    valid_values = {1e-6, 1e-2}
    for key, value in results["best_params"].items():
        assert value in valid_values, \
            f"Parameter {key} has invalid value {value}. Must be one of {valid_values}."

    assert isinstance(results["mse"], (int, float)), "MSE must be a number."
    assert results["mse"] > 0, "MSE should be positive."

    mse_str = str(results["mse"])
    if "." in mse_str:
        decimals = len(mse_str.split(".")[1])
        assert decimals <= 4, \
            f"MSE {results['mse']} is not rounded to 4 decimal places."

    # Independently execute the specified cleaning, GridSearchCV, and validation.
    frame = pd.read_csv(csv_path)
    frame["event_count"] = frame["event_count"].fillna(frame["event_count"].median())
    frame["event_count"] = frame["event_count"].astype(int)
    frame = frame.drop(columns=expected_dropped)

    X = frame.drop(columns=["system_load"])
    y = frame["system_load"]
    param_grid = {
        "alpha_1": [1e-6, 1e-2],
        "alpha_2": [1e-6, 1e-2],
        "lambda_1": [1e-6, 1e-2],
        "lambda_2": [1e-6, 1e-2],
    }
    search = GridSearchCV(BayesianRidge(), param_grid=param_grid, cv=3)
    search.fit(X, y)
    expected_best_params = search.best_params_
    expected_mse = round(mean_squared_error(y, search.best_estimator_.predict(X)), 4)

    assert results["best_params"] == expected_best_params, \
        f"Expected best_params to be {expected_best_params}, but got {results['best_params']}."
    assert results["mse"] == expected_mse, \
        f"Expected mse to be {expected_mse}, but got {results['mse']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
