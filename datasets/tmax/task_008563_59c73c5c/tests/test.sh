#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import math
import struct
import glob
import pytest
import pandas as pd


def get_expected_summary():
    files = glob.glob('/home/user/raw_data/*.csv')
    if not files:
        return {}

    data = {}
    for f in files:
        with open(f, 'r') as csvfile:
            reader = csv.DictReader(csvfile)
            for row in reader:
                sensor = row['sensor_id']
                val = float(row['value'])
                if sensor not in data:
                    data[sensor] = {'raw': [], 'cleaned_count': 0}
                data[sensor]['raw'].append(val)
                if 0.0 <= val <= 100000.0:
                    data[sensor]['cleaned_count'] += 1

    summary = {}
    for sensor, vals in data.items():
        raw = vals['raw']
        exact_sum = math.fsum(raw)

        naive_sum = 0.0
        for v in raw:
            v_f32 = struct.unpack('f', struct.pack('f', v))[0]
            naive_f32 = struct.unpack('f', struct.pack('f', naive_sum))[0]
            naive_sum = struct.unpack('f', struct.pack('f', naive_f32 + v_f32))[0]

        abs_err = abs(exact_sum - naive_sum)

        summary[sensor] = {
            "exact_sum": round(exact_sum, 4),
            "absolute_error": round(abs_err, 4),
            "cleaned_row_count": vals['cleaned_count']
        }
    return summary


def get_expected_aggregation():
    files = sorted(glob.glob('/home/user/raw_data/*.csv'))
    assert files, "No raw CSV files were found."

    raw = pd.concat(
        [pd.read_csv(path, usecols=['timestamp', 'sensor_id', 'value']) for path in files],
        ignore_index=True
    )
    cleaned = raw[(raw['value'] >= 0.0) & (raw['value'] <= 100000.0)].copy()
    cleaned['day'] = cleaned['timestamp'] // 86400

    expected = (
        cleaned.groupby(['sensor_id', 'day'], as_index=False, sort=True)['value']
        .mean()
        .rename(columns={'value': 'mean_value'})
    )
    expected['day'] = expected['day'].astype('int64')
    expected['mean_value'] = expected['mean_value'].astype('float64')
    return expected.sort_values(['sensor_id', 'day']).reset_index(drop=True)


def test_summary_json_exists():
    assert os.path.isfile('/home/user/summary.json'), "/home/user/summary.json is missing."


def test_summary_json_contents():
    with open('/home/user/summary.json', 'r') as f:
        try:
            actual_summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/summary.json is not valid JSON.")

    expected_summary = get_expected_summary()

    assert set(actual_summary.keys()) == set(expected_summary.keys()), "Sensors in summary.json do not match expected sensors."

    for sensor in expected_summary:
        expected = expected_summary[sensor]
        actual = actual_summary[sensor]

        assert "exact_sum" in actual, f"'exact_sum' missing for {sensor}"
        assert "absolute_error" in actual, f"'absolute_error' missing for {sensor}"
        assert "cleaned_row_count" in actual, f"'cleaned_row_count' missing for {sensor}"

        assert actual["cleaned_row_count"] == expected["cleaned_row_count"], f"Incorrect cleaned_row_count for {sensor}"

        assert math.isclose(actual["exact_sum"], expected["exact_sum"], rel_tol=1e-5, abs_tol=1e-3), \
            f"exact_sum for {sensor} is incorrect. Expected {expected['exact_sum']}, got {actual['exact_sum']}"

        assert math.isclose(actual["absolute_error"], expected["absolute_error"], rel_tol=1e-4, abs_tol=1e-2), \
            f"absolute_error for {sensor} is incorrect. Expected {expected['absolute_error']}, got {actual['absolute_error']}"


def test_aggregated_parquet_exists_and_valid():
    parquet_path = '/home/user/aggregated.parquet'
    assert os.path.isfile(parquet_path), f"{parquet_path} is missing."
    assert os.path.getsize(parquet_path) > 0, f"{parquet_path} is empty."

    with open(parquet_path, 'rb') as f:
        magic = f.read(4)
        assert magic == b'PAR1', f"{parquet_path} does not appear to be a valid Parquet file (missing PAR1 magic bytes)."

    try:
        actual = pd.read_parquet(parquet_path)
    except Exception as exc:
        pytest.fail(f"{parquet_path} is not a readable Parquet file: {exc}")

    required_columns = {'sensor_id', 'day', 'mean_value'}
    assert set(actual.columns) == required_columns, \
        f"Parquet columns must be exactly {sorted(required_columns)}, got {list(actual.columns)}"
    assert pd.api.types.is_integer_dtype(actual['day'].dtype), "Parquet 'day' column must have an integer dtype."
    assert pd.api.types.is_float_dtype(actual['mean_value'].dtype), "Parquet 'mean_value' column must have a float dtype."
    assert actual['sensor_id'].map(lambda value: isinstance(value, str)).all(), \
        "Parquet 'sensor_id' values must be strings."
    assert not actual.duplicated(['sensor_id', 'day']).any(), \
        "Parquet contains duplicate sensor_id/day groups."

    expected = get_expected_aggregation()
    actual = actual[['sensor_id', 'day', 'mean_value']].sort_values(['sensor_id', 'day']).reset_index(drop=True)

    pd.testing.assert_frame_equal(
        actual,
        expected,
        check_dtype=False,
        check_exact=False,
        rtol=1e-12,
        atol=1e-9
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
