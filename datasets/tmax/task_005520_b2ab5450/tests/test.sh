#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os

import pandas as pd
import pyarrow.parquet as pq
import pytest
from pandas.testing import assert_frame_equal

PROCESSED_DIR = "/home/user/processed_data"
RESULTS_FILE = "/home/user/results/top_correlation.json"
LOCATIONS = [f"LOC_{i:03d}" for i in range(1, 6)]
NUMERIC_COLUMNS = ["traffic_volume", "temperature", "humidity", "pm25", "no2"]
EXPECTED_COLUMNS = [
    "timestamp", "location_id", "temperature", "humidity",
    "traffic_volume", "pm25", "no2"
]


def load_expected():
    weather = pd.concat(
        [pd.read_csv(path) for path in sorted(glob.glob("/home/user/raw_data/weather/*.csv"))],
        ignore_index=True,
    )
    traffic = pd.concat(
        [pd.read_csv(path) for path in sorted(glob.glob("/home/user/raw_data/traffic/*.csv"))],
        ignore_index=True,
    )
    air_quality = pd.concat(
        [pd.read_csv(path) for path in sorted(glob.glob("/home/user/raw_data/air_quality/*.csv"))],
        ignore_index=True,
    )

    expected = weather.merge(
        traffic, on=["timestamp", "location_id"], how="inner", validate="one_to_one"
    ).merge(
        air_quality, on=["timestamp", "location_id"], how="inner", validate="one_to_one"
    )
    return normalize(expected)


def normalize(frame):
    frame = frame.copy()
    assert set(frame.columns) == set(EXPECTED_COLUMNS), (
        f"Joined dataset has columns {list(frame.columns)}, expected exactly {EXPECTED_COLUMNS}."
    )
    frame = frame[EXPECTED_COLUMNS]
    frame["timestamp"] = pd.to_datetime(frame["timestamp"], errors="raise")
    frame["location_id"] = frame["location_id"].astype(str)
    for column in NUMERIC_COLUMNS:
        frame[column] = pd.to_numeric(frame[column], errors="raise").astype(float)
    return frame.sort_values(["location_id", "timestamp"]).reset_index(drop=True)


def load_submitted_parquet():
    frames = []
    for loc in LOCATIONS:
        partition_dir = os.path.join(PROCESSED_DIR, f"location_id={loc}")

        # Preserve the original partition assertions.
        assert os.path.exists(partition_dir), (
            f"Partition directory {partition_dir} does not exist. "
            "Parquet data must be partitioned by location_id."
        )
        assert os.path.isdir(partition_dir), f"Path {partition_dir} is not a directory."
        entries = os.listdir(partition_dir)
        assert len(entries) > 0, (
            f"Partition directory {partition_dir} is empty. It should contain Parquet files."
        )

        assert not any(os.path.isdir(os.path.join(partition_dir, name)) for name in entries), (
            "Only location_id partitioning was requested; nested partition directories are invalid."
        )
        files = [os.path.join(partition_dir, name) for name in entries
                 if os.path.isfile(os.path.join(partition_dir, name))]
        assert files, f"Partition {partition_dir} contains no data files."

        for path in sorted(files):
            try:
                parquet_file = pq.ParquetFile(path)
                table = parquet_file.read()
            except Exception as exc:
                pytest.fail(f"Data file {path} is not a readable Parquet file: {exc}")

            frame = table.to_pandas().reset_index(drop=True)
            if "location_id" in frame.columns:
                values = frame["location_id"].astype(str)
                assert (values == loc).all(), (
                    f"Parquet file {path} contains rows outside partition {loc}."
                )
            else:
                frame["location_id"] = loc
            frames.append(frame)

    assert frames, "No readable Parquet data files were found."
    return normalize(pd.concat(frames, ignore_index=True))


def expected_top_correlation(expected):
    matrix = expected[NUMERIC_COLUMNS].corr(method="pearson")
    candidates = []
    for i, first in enumerate(NUMERIC_COLUMNS):
        for second in NUMERIC_COLUMNS[i + 1:]:
            candidates.append((abs(float(matrix.loc[first, second])), first, second))
    _, first, second = max(candidates, key=lambda item: item[0])
    var1, var2 = sorted([first, second])
    return var1, var2, round(float(matrix.loc[first, second]), 4)


def test_parquet_partitioning_and_contents():
    """Verify genuine partitioned Parquet contains the exact inner-joined rows."""
    assert os.path.exists(PROCESSED_DIR), f"Directory {PROCESSED_DIR} does not exist."
    assert os.path.isdir(PROCESSED_DIR), f"Path {PROCESSED_DIR} is not a directory."

    expected = load_expected()
    actual = load_submitted_parquet()
    assert_frame_equal(actual, expected, check_dtype=False, rtol=1e-10, atol=1e-10)


def test_correlation_results():
    """Verify the report structure and independently derived correlation result."""
    assert os.path.exists(RESULTS_FILE), f"Results file {RESULTS_FILE} does not exist."
    assert os.path.isfile(RESULTS_FILE), f"Path {RESULTS_FILE} is not a file."

    with open(RESULTS_FILE, "r") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_FILE} does not contain valid JSON.")

    for key in ["var1", "var2", "correlation"]:
        assert key in data, f"Key '{key}' is missing in the JSON file."
    assert set(data) == {"var1", "var2", "correlation"}, (
        "The JSON file must contain exactly var1, var2, and correlation."
    )

    # Preserve the original known-answer assertions.
    assert data["var1"] == "no2", f"Expected var1 to be 'no2', got '{data['var1']}'."
    assert data["var2"] == "traffic_volume", (
        f"Expected var2 to be 'traffic_volume', got '{data['var2']}'."
    )
    correlation = data["correlation"]
    assert isinstance(correlation, (int, float)) and not isinstance(correlation, bool), (
        f"Expected correlation to be a number, got {type(correlation).__name__}."
    )
    assert math.isclose(correlation, 0.9232, abs_tol=0.0002), (
        f"Expected correlation to be approximately 0.9232, got {correlation}."
    )

    expected_var1, expected_var2, expected_value = expected_top_correlation(load_expected())
    assert data["var1"] == expected_var1
    assert data["var2"] == expected_var2
    assert data["correlation"] == expected_value, (
        f"Expected independently computed rounded correlation {expected_value}, "
        f"got {data['correlation']}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
