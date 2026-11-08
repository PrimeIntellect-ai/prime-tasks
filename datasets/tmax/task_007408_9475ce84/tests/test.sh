#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import json
import math
import os
import subprocess

import numpy as np
import pandas as pd
from scipy import stats

SCRIPT_PATH = "/home/user/clean_pipeline.py"
CSV_PATH = "/home/user/sensor_data.csv"
JSON_PATH = "/home/user/cleaning_summary.json"
SENSORS = ["sensor_A", "sensor_B", "sensor_C"]


def run_submission():
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"clean_pipeline.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(JSON_PATH), f"The output file {JSON_PATH} was not created."
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is not a file."
    try:
        with open(JSON_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"The file {JSON_PATH} does not contain valid JSON.") from exc


def assert_required_shape(data):
    expected_keys = [
        "correlated_pair",
        "correlation_coefficient",
        "removed_anomalies_count",
        "t_test_p_value",
    ]
    for key in expected_keys:
        assert key in data, f"Key '{key}' is missing from {JSON_PATH}."
    assert isinstance(data["correlated_pair"], list), "correlated_pair must be a list."
    assert isinstance(data["correlation_coefficient"], (int, float)), (
        "correlation_coefficient must be a number."
    )
    assert isinstance(data["removed_anomalies_count"], int), (
        "removed_anomalies_count must be an integer."
    )
    assert isinstance(data["t_test_p_value"], (int, float)), (
        "t_test_p_value must be a number."
    )


def expected_summary(frame):
    df = frame.copy()
    df[SENSORS] = df[SENSORS].interpolate(method="linear")
    corr = df[SENSORS].corr(method="pearson")

    pairs = list(itertools.combinations(SENSORS, 2))
    pair = max(pairs, key=lambda p: abs(float(corr.loc[p[0], p[1]])))
    pair = tuple(sorted(pair))
    x_name, y_name = pair

    x = df[x_name].to_numpy(dtype=float)
    y = df[y_name].to_numpy(dtype=float)
    design = np.column_stack([x, np.ones(len(x))])
    slope, intercept = np.linalg.lstsq(design, y, rcond=None)[0]
    residuals = y - (slope * x + intercept)
    residual_std = np.std(residuals, ddof=1)
    keep = np.abs(residuals) <= 3 * residual_std
    cleaned = df.loc[keep]

    split = len(cleaned) // 2
    first = cleaned["sensor_C"].iloc[:split]
    second = cleaned["sensor_C"].iloc[split:]
    p_value = stats.ttest_ind(first, second, equal_var=False).pvalue

    return {
        "correlated_pair": list(pair),
        "correlation_coefficient": round(float(corr.loc[pair[0], pair[1]]), 4),
        "removed_anomalies_count": int((~keep).sum()),
        "t_test_p_value": round(float(p_value), 4),
    }


def assert_matches(data, expected):
    assert_required_shape(data)
    assert sorted(data["correlated_pair"]) == expected["correlated_pair"], (
        f"Expected correlated_pair to be {expected['correlated_pair']}, "
        f"got {data['correlated_pair']}."
    )
    assert math.isclose(
        data["correlation_coefficient"],
        expected["correlation_coefficient"],
        abs_tol=1e-4,
    ), (
        f"Expected correlation_coefficient to be close to "
        f"{expected['correlation_coefficient']}, got {data['correlation_coefficient']}."
    )
    assert data["removed_anomalies_count"] == expected["removed_anomalies_count"], (
        f"Expected removed_anomalies_count to be "
        f"{expected['removed_anomalies_count']}, got "
        f"{data['removed_anomalies_count']}."
    )
    assert math.isclose(
        data["t_test_p_value"], expected["t_test_p_value"], abs_tol=1e-4
    ), (
        f"Expected t_test_p_value to be close to {expected['t_test_p_value']}, "
        f"got {data['t_test_p_value']}."
    )


def make_case(seed, correlated_pair):
    rng = np.random.default_rng(seed)
    n = 121
    latent = np.linspace(-8, 12, n) + rng.normal(0, 0.35, n)

    if correlated_pair == "AB":
        sensor_a = latent + rng.normal(0, 0.12, n)
        sensor_b = 2.7 * sensor_a - 4.5 + rng.normal(0, 0.25, n)
        sensor_c = rng.normal(30, 7, n) + np.r_[np.zeros(60), np.full(61, 3.0)]
        sensor_b[[9, 37, 74, 109]] += np.array([35.0, -40.0, 38.0, -36.0])
    else:
        sensor_b = latent + rng.normal(0, 0.13, n)
        sensor_c = -2.2 * sensor_b + 18.0 + rng.normal(0, 0.3, n)
        sensor_a = rng.normal(5, 6, n) + np.r_[np.zeros(60), np.full(61, -2.0)]
        sensor_c[[11, 42, 83, 113]] += np.array([31.0, -34.0, 37.0, -32.0])

    sensor_a[[7, 55, 96]] = np.nan
    sensor_b[[18, 63, 101]] = np.nan
    sensor_c[[24, 68, 104]] = np.nan

    return pd.DataFrame({
        "timestamp": pd.date_range("2025-01-01", periods=n, freq="2h"),
        "sensor_A": sensor_a,
        "sensor_B": sensor_b,
        "sensor_C": sensor_c,
    })


def test_pipeline_executes_and_generalizes():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    try:
        # Preserve the original verifier's assertions, but only after executing the script.
        original_data = run_submission()
        original_expected = {
            "correlated_pair": ["sensor_A", "sensor_B"],
            "correlation_coefficient": 0.9859,
            "removed_anomalies_count": 14,
            "t_test_p_value": 0.0528,
        }
        assert_matches(original_data, original_expected)

        # Exercise the submitted pipeline on unseen datasets and derive each answer.
        for seed, pair in [(1729, "AB"), (8843, "BC")]:
            frame = make_case(seed, pair)
            expected = expected_summary(frame)
            frame.to_csv(CSV_PATH, index=False)
            actual = run_submission()
            assert_matches(actual, expected)
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)

    # Leave the required report generated for the original input.
    final_data = run_submission()
    assert_matches(final_data, {
        "correlated_pair": ["sensor_A", "sensor_B"],
        "correlation_coefficient": 0.9859,
        "removed_anomalies_count": 14,
        "t_test_p_value": 0.0528,
    })
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
