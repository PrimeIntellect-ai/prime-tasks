#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

import numpy as np
import pandas as pd
from pandas.api.types import is_numeric_dtype


def expected_dataframe():
    raw = pd.read_csv("/home/user/sensor_data.csv")
    expected = raw.copy()
    expected["sensor_A"] = expected["sensor_A"].interpolate(method="linear")
    lower = raw["sensor_B"].quantile(0.01)
    upper = raw["sensor_B"].quantile(0.99)
    expected["sensor_B"] = raw["sensor_B"].clip(lower=lower, upper=upper)
    expected["signal_ratio"] = (
        expected["sensor_A"] / (expected["sensor_B"] + 0.001)
    ).round(4)
    return expected


def test_parquet_file_created_and_valid():
    parquet_path = "/home/user/clean_sensors.parquet"
    assert os.path.isfile(parquet_path), f"The file {parquet_path} was not created."

    # Preserve the original physical Parquet checks.
    with open(parquet_path, "rb") as f:
        header = f.read(4)
        f.seek(-4, 2)
        footer = f.read(4)

    assert header == b"PAR1", f"File {parquet_path} is not a valid Parquet file (missing PAR1 header)."
    assert footer == b"PAR1", f"File {parquet_path} is not a valid Parquet file (missing PAR1 footer)."

    actual = pd.read_parquet(parquet_path)
    expected = expected_dataframe()

    assert list(actual.columns) == ["timestamp", "sensor_A", "sensor_B", "signal_ratio"]
    assert len(actual) == len(expected)
    assert actual.index.is_unique

    for column in ["sensor_A", "sensor_B", "signal_ratio"]:
        assert is_numeric_dtype(actual[column]), f"{column} must be numeric"
        np.testing.assert_allclose(
            actual[column].to_numpy(dtype=float),
            expected[column].to_numpy(dtype=float),
            rtol=0,
            atol=1e-12,
            equal_nan=True,
            err_msg=f"Incorrect values in {column}",
        )

    actual_timestamps = pd.to_datetime(actual["timestamp"], errors="raise").to_numpy(dtype="datetime64[ns]")
    expected_timestamps = pd.to_datetime(expected["timestamp"], errors="raise").to_numpy(dtype="datetime64[ns]")
    np.testing.assert_array_equal(actual_timestamps, expected_timestamps)


def test_metrics_log_created_and_correct():
    log_path = "/home/user/metrics.log"
    assert os.path.isfile(log_path), f"The file {log_path} was not created."

    with open(log_path, "r") as f:
        content = f.read().strip()

    # Preserve the original assertion and additionally derive the answer from the input.
    assert content == "0.1197", f"Expected metrics.log to contain '0.1197', but found '{content}'."
    expected_metric = expected_dataframe()["signal_ratio"].mean()
    expected_content = f"{expected_metric:.4f}"
    assert content == expected_content, (
        f"metrics.log does not contain the input-derived rounded mean: "
        f"expected '{expected_content}', found '{content}'"
    )

    stored = pd.read_parquet("/home/user/clean_sensors.parquet")
    stored_content = f"{stored['signal_ratio'].mean():.4f}"
    assert content == stored_content, "metrics.log does not match the stored signal_ratio mean"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
