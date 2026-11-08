#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import numpy as np
import pandas as pd

HOURLY_SUMMARY_PATH = '/home/user/hourly_summary.csv'
HIGH_RISK_SAMPLE_PATH = '/home/user/high_risk_sample.csv'
RAW_PATH = '/home/user/raw_telemetry.csv'
REQUIRED_COLS = ['timestamp', 'truck_id', 'max_temp', 'avg_speed', 'rolling_3h_max_temp']


def read_csv_as_dicts(file_path):
    assert os.path.exists(file_path), f"File not found: {file_path}"
    with open(file_path, 'r', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def assert_raw_input_unchanged():
    raw = pd.read_csv(RAW_PATH, parse_dates=['timestamp'])
    expected = pd.DataFrame([
        ['2023-10-01 08:00:00', 'TRUCK_A', -15.0, 60.0],
        ['2023-10-01 08:04:00', 'TRUCK_A', np.nan, np.nan],
        ['2023-10-01 08:11:00', 'TRUCK_A', -12.0, 70.0],
        ['2023-10-01 09:05:00', 'TRUCK_A', -8.0, 80.0],
        ['2023-10-01 10:02:00', 'TRUCK_A', -16.0, 65.0],
        ['2023-10-01 11:05:00', 'TRUCK_A', -7.0, 78.0],
        ['2023-10-01 08:00:00', 'TRUCK_B', -18.0, 65.0],
        ['2023-10-01 09:05:00', 'TRUCK_B', -18.0, 65.0],
        ['2023-10-01 10:05:00', 'TRUCK_B', -9.0, 85.0],
        ['2023-10-01 11:05:00', 'TRUCK_B', -17.0, 60.0],
    ], columns=['timestamp', 'truck_id', 'temperature', 'speed'])
    expected['timestamp'] = pd.to_datetime(expected['timestamp'])

    assert list(raw.columns) == list(expected.columns), 'raw_telemetry.csv schema was changed'
    raw = raw.sort_values(['truck_id', 'timestamp']).reset_index(drop=True)
    expected = expected.sort_values(['truck_id', 'timestamp']).reset_index(drop=True)
    assert raw[['timestamp', 'truck_id']].equals(expected[['timestamp', 'truck_id']]), 'raw_telemetry.csv records were changed'
    np.testing.assert_allclose(raw['temperature'], expected['temperature'], rtol=0, atol=0, equal_nan=True)
    np.testing.assert_allclose(raw['speed'], expected['speed'], rtol=0, atol=0, equal_nan=True)


def build_reference():
    raw = pd.read_csv(RAW_PATH, parse_dates=['timestamp'])
    hourly_parts = []

    for truck_id, group in raw.groupby('truck_id', sort=True):
        five_minute = (
            group.sort_values('timestamp')
                 .set_index('timestamp')[['temperature', 'speed']]
                 .resample('5min')
                 .mean()
        )
        five_minute['temperature'] = five_minute['temperature'].ffill(limit=2)
        five_minute['speed'] = five_minute['speed'].interpolate(method='linear')

        hourly = five_minute.resample('1h').agg(
            max_temp=('temperature', 'max'),
            avg_speed=('speed', 'mean'),
        ).reset_index()
        hourly.insert(1, 'truck_id', truck_id)
        hourly['rolling_3h_max_temp'] = hourly['max_temp'].rolling(
            window=3, min_periods=1
        ).mean()
        hourly_parts.append(hourly)

    hourly = pd.concat(hourly_parts, ignore_index=True)[REQUIRED_COLS]
    high_risk = hourly[(hourly['max_temp'] > -10.0) | (hourly['avg_speed'] > 75.0)]
    sample = (
        high_risk.sort_values(['truck_id', 'max_temp', 'timestamp'], ascending=[True, False, True])
                 .groupby('truck_id', as_index=False, sort=True)
                 .head(1)
                 .reset_index(drop=True)[REQUIRED_COLS]
    )
    return hourly, sample


def load_output(path):
    assert os.path.isfile(path), f"File not found: {path}"
    frame = pd.read_csv(path)
    assert len(frame) > 0, f"{os.path.basename(path)} is empty"
    assert set(REQUIRED_COLS).issubset(frame.columns), f"Missing columns in {path}"
    try:
        frame['timestamp'] = pd.to_datetime(frame['timestamp'], errors='raise')
        for column in ['max_temp', 'avg_speed', 'rolling_3h_max_temp']:
            frame[column] = pd.to_numeric(frame[column], errors='raise')
    except Exception as exc:
        raise AssertionError(f"Invalid timestamp or numeric data in {path}: {exc}")
    return frame[REQUIRED_COLS]


def assert_frame_matches(actual, expected, name):
    key = ['truck_id', 'timestamp']
    assert not actual.duplicated(key).any(), f"{name} contains duplicate truck/hour rows"
    actual = actual.sort_values(key).reset_index(drop=True)
    expected = expected.sort_values(key).reset_index(drop=True)

    assert len(actual) == len(expected), f"{name} has {len(actual)} rows; expected {len(expected)}"
    assert actual[key].equals(expected[key]), f"{name} has missing, extra, or incorrect truck/hour rows"
    for column in ['max_temp', 'avg_speed', 'rolling_3h_max_temp']:
        np.testing.assert_allclose(
            actual[column].to_numpy(dtype=float),
            expected[column].to_numpy(dtype=float),
            rtol=1e-7,
            atol=1e-7,
            equal_nan=True,
            err_msg=f"Incorrect {column} values in {name}",
        )


def test_hourly_summary_exists_and_columns():
    data = read_csv_as_dicts(HOURLY_SUMMARY_PATH)
    assert len(data) > 0, 'hourly_summary.csv is empty.'
    expected_cols = set(REQUIRED_COLS)
    actual_cols = set(data[0].keys())
    assert expected_cols.issubset(actual_cols), f"Missing columns in hourly_summary.csv. Expected {expected_cols}, got {actual_cols}"


def test_high_risk_sample_exists_and_columns():
    data = read_csv_as_dicts(HIGH_RISK_SAMPLE_PATH)
    assert len(data) > 0, 'high_risk_sample.csv is empty.'
    expected_cols = set(REQUIRED_COLS)
    actual_cols = set(data[0].keys())
    assert expected_cols.issubset(actual_cols), f"Missing columns in high_risk_sample.csv. Expected {expected_cols}, got {actual_cols}"


def test_hourly_summary_computations():
    data = read_csv_as_dicts(HOURLY_SUMMARY_PATH)
    truck_a_data = [row for row in data if row['truck_id'] == 'TRUCK_A']
    truck_a_data.sort(key=lambda x: x['timestamp'])
    assert len(truck_a_data) >= 4, 'Not enough hourly records for TRUCK_A'
    hour_0_max_temp = float(truck_a_data[0]['max_temp'])
    assert abs(hour_0_max_temp - (-12.0)) < 0.01
    hour_2_rolling = float(truck_a_data[2]['rolling_3h_max_temp'])
    assert abs(hour_2_rolling - (-12.0)) < 0.01


def test_high_risk_sample_computations():
    data = read_csv_as_dicts(HIGH_RISK_SAMPLE_PATH)
    assert len(data) == 2, f"high_risk_sample.csv should have exactly 2 rows (1 per truck), got {len(data)}"
    truck_a_rows = [row for row in data if row['truck_id'] == 'TRUCK_A']
    truck_b_rows = [row for row in data if row['truck_id'] == 'TRUCK_B']
    assert len(truck_a_rows) == 1
    assert len(truck_b_rows) == 1
    assert abs(float(truck_a_rows[0]['max_temp']) - (-7.0)) < 0.01
    assert abs(float(truck_b_rows[0]['max_temp']) - (-9.0)) < 0.01


def test_complete_pipeline_outputs():
    assert_raw_input_unchanged()
    expected_hourly, expected_sample = build_reference()
    actual_hourly = load_output(HOURLY_SUMMARY_PATH)
    actual_sample = load_output(HIGH_RISK_SAMPLE_PATH)
    assert_frame_matches(actual_hourly, expected_hourly, 'hourly_summary.csv')
    assert_frame_matches(actual_sample, expected_sample, 'high_risk_sample.csv')

    merged = actual_sample.merge(
        actual_hourly,
        on=['timestamp', 'truck_id'],
        how='left',
        suffixes=('_sample', '_hourly'),
        validate='one_to_one',
    )
    assert len(merged) == len(actual_sample)
    for column in ['max_temp', 'avg_speed', 'rolling_3h_max_temp']:
        np.testing.assert_allclose(
            merged[f'{column}_sample'], merged[f'{column}_hourly'],
            rtol=1e-7, atol=1e-7, equal_nan=True,
            err_msg=f"Sample {column} does not match its hourly source row",
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
