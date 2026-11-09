#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import numpy as np
import pandas as pd
from sklearn.linear_model import BayesianRidge
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA


def test_result_file_exists():
    """Test that the result.txt file exists."""
    file_path = "/home/user/result.txt"
    assert os.path.exists(file_path), f"The result file {file_path} is missing."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."


def test_result_file_format_and_content():
    """Test that the result.txt file contains exactly 3 valid sensor IDs."""
    result_path = "/home/user/result.txt"
    dataset_path = "/home/user/sensor_data.csv"

    assert os.path.exists(result_path), "Cannot check format because result.txt is missing."
    assert os.path.exists(dataset_path), "Cannot validate sensors because sensor_data.csv is missing."

    with open(result_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 sensor IDs in result.txt, but found {len(lines)}."

    with open(dataset_path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        valid_sensors = set(row[0] for row in reader if row)

    for sensor in lines:
        assert sensor in valid_sensors, f"Output contains invalid sensor ID: '{sensor}'."
        assert sensor != "sensor_0", "The results should exclude 'sensor_0' itself."

    assert len(set(lines)) == 3, "The result.txt file contains duplicate sensor IDs."


def test_result_matches_requested_pipeline():
    """Independently recompute the complete pipeline and verify ordered neighbors."""
    dataset_path = "/home/user/sensor_data.csv"
    result_path = "/home/user/result.txt"

    df = pd.read_csv(dataset_path)
    required = ["sensor_id", "f1", "f2", "f3", "f4", "target_f"]
    assert all(column in df.columns for column in required), "Dataset is missing required columns."
    assert (df["sensor_id"] == "sensor_0").sum() == 1, "Dataset must contain exactly one sensor_0."

    predictors = ["f1", "f2", "f3", "f4"]
    missing = df["target_f"].isna()
    if missing.any():
        model = BayesianRidge()
        model.fit(df.loc[~missing, predictors], df.loc[~missing, "target_f"])
        df.loc[missing, "target_f"] = model.predict(df.loc[missing, predictors])

    percentile_95 = df["f3"].quantile(0.95)
    df = df.loc[df["f3"] <= percentile_95].copy()
    assert (df["sensor_id"] == "sensor_0").sum() == 1, "sensor_0 was removed by filtering."

    df["f_combo"] = df["f1"] * df["f2"]
    features = ["f1", "f2", "f3", "f4", "target_f", "f_combo"]
    standardized = StandardScaler().fit_transform(df[features])
    points = PCA(n_components=2, random_state=42).fit_transform(standardized)

    query_index = np.flatnonzero(df["sensor_id"].to_numpy() == "sensor_0")[0]
    distances = np.linalg.norm(points - points[query_index], axis=1)
    distances[query_index] = np.inf
    nearest_indices = np.argsort(distances)[:3]
    expected = df.iloc[nearest_indices]["sensor_id"].astype(str).tolist()

    with open(result_path, "r") as f:
        actual = [line.strip() for line in f if line.strip()]

    assert actual == expected, (
        "result.txt does not contain the three nearest sensors in closest-to-furthest order. "
        f"Expected {expected}, got {actual}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
