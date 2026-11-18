#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os

import numpy as np
import pandas as pd

RAW_PATH = "/home/user/sensor_data.csv"
RESULTS_PATH = "/home/user/integration_results.csv"
MAX_PATH = "/home/user/max_sensor.txt"


def expected_areas():
    assert os.path.exists(RAW_PATH), f"Original data file was deleted: {RAW_PATH}"
    assert os.path.isfile(RAW_PATH), f"Expected a file, but found a directory: {RAW_PATH}"

    df = pd.read_csv(RAW_PATH)
    assert list(df.columns) == ["timestamp", "sensor_id", "value"], \
        f"Unexpected source columns: {list(df.columns)}"

    cleaned = df.copy()
    means = cleaned.groupby("sensor_id")["value"].transform("mean")
    stds = cleaned.groupby("sensor_id")["value"].transform("std")
    outliers = (cleaned["value"] - means).abs() > (3 * stds)
    cleaned.loc[outliers, "value"] = np.nan
    cleaned = cleaned.sort_values("timestamp", ascending=True)

    areas = {}
    for sensor_id, group in cleaned.groupby("sensor_id"):
        group = group.sort_values("timestamp")
        timestamps = group["timestamp"].astype(float).to_numpy()
        values = pd.Series(
            group["value"].astype(float).to_numpy(),
            index=timestamps,
        )
        values = values.interpolate(method="index").ffill().bfill()
        assert not values.isna().any(), f"Reference cleaning left NaNs for {sensor_id}"

        if hasattr(np, "trapezoid"):
            area = np.trapezoid(values.to_numpy(), timestamps)
        else:
            area = np.trapz(values.to_numpy(), timestamps)
        areas[str(sensor_id)] = float(area)

    return areas


def test_integration_results_csv():
    """Test that integration_results.csv exists, has correct columns, order, and areas."""
    assert os.path.exists(RESULTS_PATH), f"File not found: {RESULTS_PATH}"
    assert os.path.isfile(RESULTS_PATH), \
        f"Expected a file, but found a directory: {RESULTS_PATH}"

    with open(RESULTS_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, f"File is empty: {RESULTS_PATH}"

        expected_columns = ["sensor_id", "total_area"]
        assert header == expected_columns, \
            f"Expected columns {expected_columns}, got {header}"

        rows = list(reader)
        assert len(rows) > 0, "No data rows found in integration_results.csv"

        sensor_ids = [row[0] for row in rows]
        assert sensor_ids == sorted(sensor_ids), \
            "The integration results are not sorted alphabetically by sensor_id"
        assert set(sensor_ids) == {"A", "B", "C"}, \
            "Expected sensor_ids A, B, C in the results"
        assert len(rows) == 3, "Expected exactly one result row for each sensor"

        expected = expected_areas()
        for row in rows:
            assert len(row) == 2, f"Expected two columns in result row, got {row}"
            sensor_id, area_text = row
            try:
                actual_area = float(area_text)
            except ValueError:
                raise AssertionError(
                    f"total_area for sensor {sensor_id} is not numeric: {area_text!r}"
                )
            assert math.isfinite(actual_area), \
                f"total_area for sensor {sensor_id} is not finite"
            assert math.isclose(
                actual_area, expected[sensor_id], rel_tol=1e-7, abs_tol=1e-6
            ), (
                f"Incorrect total_area for sensor {sensor_id}: "
                f"expected {expected[sensor_id]}, got {actual_area}"
            )


def test_max_sensor_txt():
    """Test that max_sensor.txt exists and contains the correctly derived result."""
    assert os.path.exists(MAX_PATH), f"File not found: {MAX_PATH}"
    assert os.path.isfile(MAX_PATH), \
        f"Expected a file, but found a directory: {MAX_PATH}"

    with open(MAX_PATH, "r") as f:
        content = f.read().strip()

    assert content, "max_sensor.txt is empty"

    # Preserve the original assertion.
    assert content.startswith("B,25.0") or content.startswith("B,25.1"), \
        f"Expected max_sensor.txt to start with 'B,25.0' or 'B,25.1', but got '{content}'"

    expected = expected_areas()
    max_sensor = max(expected, key=expected.get)
    expected_content = f"{max_sensor},{expected[max_sensor]:.2f}"
    assert content == expected_content, \
        f"Expected max_sensor.txt to contain exactly {expected_content!r}, got {content!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
