#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import subprocess

import numpy as np
import pandas as pd
import pytest
from sklearn.decomposition import PCA
from sklearn.ensemble import IsolationForest

INPUT_PATH = "/home/user/data/sensor_readings.csv"
SCRIPT_PATH = "/home/user/etl_pipeline.py"
OUTPUT_PATH = "/home/user/output/final_pipeline_output.csv"


def validate_original_input(raw):
    """Ensure the agent has not replaced the fixed task input."""
    rng = np.random.RandomState(42)
    sensor_a = rng.normal(10, 2, 100)
    sensor_b = sensor_a * 0.95 + rng.normal(0, 0.3, 100)
    sensor_c = rng.normal(20, 5, 100)
    expected_timestamps = pd.date_range("2023-01-01", periods=100, freq="h")

    assert list(raw.columns) == ["timestamp", "sensor_A", "sensor_B", "sensor_C"]
    assert len(raw) == 100
    assert pd.to_datetime(raw["timestamp"]).tolist() == expected_timestamps.tolist(), \
        "The supplied input timestamps were modified."
    np.testing.assert_allclose(raw["sensor_A"].to_numpy(), sensor_a, rtol=1e-12, atol=1e-12)
    np.testing.assert_allclose(raw["sensor_B"].to_numpy(), sensor_b, rtol=1e-12, atol=1e-12)
    np.testing.assert_allclose(raw["sensor_C"].to_numpy(), sensor_c, rtol=1e-12, atol=1e-12)


def compute_expected(raw):
    df = raw.copy()
    df["timestamp"] = pd.to_datetime(df["timestamp"])
    df = df.sort_values("timestamp").reset_index(drop=True)

    sensor_columns = ["sensor_A", "sensor_B", "sensor_C"]
    for column in sensor_columns:
        df[column + "_roll"] = df[column].rolling(window=3).mean()
    df = df.dropna().reset_index(drop=True)

    feature_columns = [
        "sensor_A", "sensor_B", "sensor_C",
        "sensor_A_roll", "sensor_B_roll", "sensor_C_roll",
    ]
    correlations = df[feature_columns].corr(method="pearson")
    dropped = set()
    for i in range(len(feature_columns)):
        for j in range(i + 1, len(feature_columns)):
            left = feature_columns[i]
            right = feature_columns[j]
            if left in dropped or right in dropped:
                continue
            if abs(correlations.loc[left, right]) >= 0.90:
                dropped.add(max(left, right))

    selected = [column for column in feature_columns if column not in dropped]
    components = PCA(n_components=2, random_state=42).fit_transform(df[selected])
    model = IsolationForest(random_state=42, contamination=0.1)
    model.fit(components)

    return pd.DataFrame({
        "timestamp": df["timestamp"].astype(str),
        "pca_0": components[:, 0],
        "pca_1": components[:, 1],
        "anomaly_score": model.decision_function(components),
        "is_anomaly": model.predict(components),
    })


@pytest.fixture(scope="session", autouse=True)
def pipeline_result():
    assert os.path.isfile(SCRIPT_PATH), f"Pipeline script {SCRIPT_PATH} is missing."
    assert os.path.getsize(SCRIPT_PATH) > 0, "Pipeline script is empty."
    assert os.path.isfile(INPUT_PATH), f"Input file {INPUT_PATH} is missing."

    raw = pd.read_csv(INPUT_PATH)
    validate_original_input(raw)
    expected = compute_expected(raw)

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        check=True,
        timeout=120,
    )
    return expected


def test_output_file_exists():
    """Check if the final output CSV file was created."""
    file_path = "/home/user/output/final_pipeline_output.csv"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."


def test_output_file_structure_and_types():
    """Check the structure, headers, row count, and data types of the output CSV."""
    file_path = "/home/user/output/final_pipeline_output.csv"

    with open(file_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("Output CSV is empty.")

        expected_header = ['timestamp', 'pca_0', 'pca_1', 'anomaly_score', 'is_anomaly']
        assert header == expected_header, f"Header mismatch. Expected {expected_header}, got {header}"

        rows = list(reader)

        # 100 original rows - 2 dropped due to rolling window of 3 = 98 rows
        assert len(rows) == 98, f"Expected exactly 98 data rows, got {len(rows)}"

        for i, row in enumerate(rows):
            assert len(row) == 5, f"Row {i+1} has {len(row)} columns, expected 5."
            assert row[0].strip(), f"Row {i+1} has an empty timestamp."

            try:
                float(row[1])
            except ValueError:
                pytest.fail(f"Row {i+1}: pca_0 '{row[1]}' cannot be parsed as float.")

            try:
                float(row[2])
            except ValueError:
                pytest.fail(f"Row {i+1}: pca_1 '{row[2]}' cannot be parsed as float.")

            try:
                float(row[3])
            except ValueError:
                pytest.fail(f"Row {i+1}: anomaly_score '{row[3]}' cannot be parsed as float.")

            assert row[4] in ['1', '-1', '1.0', '-1.0'], \
                f"Row {i+1}: is_anomaly '{row[4]}' must be 1 or -1."


def test_pipeline_values_match_required_computation(pipeline_result):
    actual = pd.read_csv(OUTPUT_PATH)
    expected = pipeline_result

    assert actual["timestamp"].astype(str).tolist() == expected["timestamp"].tolist(), \
        "Output timestamps do not match the chronologically sorted, rolling-window-filtered input."

    for column in ["pca_0", "pca_1", "anomaly_score"]:
        values = actual[column].to_numpy(dtype=float)
        assert np.isfinite(values).all(), f"{column} contains non-finite values."
        np.testing.assert_allclose(
            values,
            expected[column].to_numpy(dtype=float),
            rtol=1e-7,
            atol=1e-8,
            err_msg=f"{column} does not match the required pipeline computation.",
        )

    actual_labels = actual["is_anomaly"].to_numpy(dtype=float)
    np.testing.assert_array_equal(actual_labels, expected["is_anomaly"].to_numpy(dtype=int))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
