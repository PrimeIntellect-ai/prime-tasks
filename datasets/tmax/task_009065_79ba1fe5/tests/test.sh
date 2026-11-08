#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq


def hash_uid(uid):
    return "anon_" + hashlib.sha256(uid.encode('utf-8')).hexdigest()


def expected_unified():
    # Reconstruct the expected result from the original device-native records.
    device_a = pd.DataFrame({
        'date_time': ['2023-10-01 10:00:00', '2023-10-01 10:05:00', '2023-10-01 10:10:00'],
        'patient_id': ['patient_1', 'patient_1', 'patient_2'],
        'hr': [75.0, 110.0, 38.0],
    }).rename(columns={'date_time': 'timestamp', 'patient_id': 'user_id', 'hr': 'value'})

    device_b = pd.DataFrame([
        {'ts': '2023-10-01T10:02:00Z', 'uid': 'patient_2', 'heart_rate': 80.0},
        {'ts': '2023-10-01T10:15:00Z', 'uid': 'patient_1', 'heart_rate': 160.0},
        {'ts': '2023-10-01T10:20:00Z', 'uid': 'patient_3', 'heart_rate': 90.0},
    ]).rename(columns={'ts': 'timestamp', 'uid': 'user_id', 'heart_rate': 'value'})

    device_c = pd.DataFrame({
        'timestamp': ['2023-10-01 10:04:00', '2023-10-01 10:25:00'],
        'user': ['patient_3', 'patient_3'],
        'bpm': [65.0, 60.0],
    }).rename(columns={'user': 'user_id', 'bpm': 'value'})

    result = pd.concat([device_a, device_b, device_c], ignore_index=True)
    result = result[['timestamp', 'user_id', 'value']]
    result['timestamp'] = pd.to_datetime(result['timestamp'], utc=True).dt.strftime('%Y-%m-%d %H:%M:%S')
    result['user_id'] = result['user_id'].map(hash_uid)
    result['value'] = result['value'].astype(float)
    return result.sort_values('timestamp', kind='stable').reset_index(drop=True)


def expected_alerts():
    source = expected_unified()
    previous = {}
    alerts = []
    for row in source.itertuples(index=False):
        anomaly = row.value < 40.0 or row.value > 150.0
        changepoint = row.user_id in previous and abs(row.value - previous[row.user_id]) > 30.0
        previous[row.user_id] = row.value
        if anomaly or changepoint:
            alert_type = 'both' if anomaly and changepoint else ('anomaly' if anomaly else 'changepoint')
            alerts.append({
                'timestamp': row.timestamp,
                'user_id': row.user_id,
                'value': row.value,
                'alert_type': alert_type,
            })
    return alerts


def canonical_timestamp(value):
    assert isinstance(value, str), f"Timestamp must be stored as a string, got {type(value).__name__}."
    return pd.to_datetime(value, utc=True, errors='raise').strftime('%Y-%m-%d %H:%M:%S')


def test_processed_directory_exists():
    assert os.path.isdir('/home/user/processed'), "The /home/user/processed directory was not created."


def test_unified_parquet_exists_and_valid():
    file_path = '/home/user/processed/unified.parquet'
    assert os.path.isfile(file_path), f"{file_path} is missing."

    # Preserve the original Parquet magic-byte checks.
    with open(file_path, 'rb') as f:
        header = f.read(4)
        f.seek(-4, os.SEEK_END)
        footer = f.read(4)
    assert header == b'PAR1', "unified.parquet does not have a valid Parquet header."
    assert footer == b'PAR1', "unified.parquet does not have a valid Parquet footer."

    # Parse the artifact as Parquet and verify its complete schema and contents.
    table = pq.read_table(file_path)
    assert table.column_names == ['timestamp', 'user_id', 'value'], \
        f"Unexpected Parquet columns: {table.column_names}."
    assert table.num_rows == 8, f"Expected all 8 input records, found {table.num_rows}."
    assert pa.types.is_string(table.schema.field('timestamp').type) or pa.types.is_large_string(table.schema.field('timestamp').type), \
        "timestamp must be stored as a string column."
    assert pa.types.is_string(table.schema.field('user_id').type) or pa.types.is_large_string(table.schema.field('user_id').type), \
        "user_id must be stored as a string column."
    assert pa.types.is_integer(table.schema.field('value').type) or pa.types.is_floating(table.schema.field('value').type), \
        "value must be a numeric column."

    actual = table.to_pandas()
    assert not actual.isnull().any().any(), "unified.parquet contains null values."
    actual['timestamp'] = actual['timestamp'].map(canonical_timestamp)
    actual['value'] = pd.to_numeric(actual['value'], errors='raise').astype(float)

    assert actual['timestamp'].tolist() == sorted(actual['timestamp'].tolist()), \
        "unified.parquet is not sorted chronologically."
    pd.testing.assert_frame_equal(
        actual.reset_index(drop=True),
        expected_unified(),
        check_dtype=False,
        check_like=False,
    )


def test_alerts_json():
    file_path = '/home/user/processed/alerts.json'
    assert os.path.isfile(file_path), f"{file_path} is missing."

    with open(file_path, 'r') as f:
        try:
            alerts = json.load(f)
        except json.JSONDecodeError:
            assert False, "alerts.json is not a valid JSON file."

    assert isinstance(alerts, list), "alerts.json must contain a JSON array."
    assert len(alerts) == 3, f"Expected exactly 3 alerts, found {len(alerts)}."

    # Preserve the original fixed alert assertions.
    expected_fixed = [
        {
            "timestamp": "2023-10-01 10:05:00",
            "user_id": hash_uid("patient_1"),
            "value": 110.0,
            "alert_type": "changepoint"
        },
        {
            "timestamp": "2023-10-01 10:10:00",
            "user_id": hash_uid("patient_2"),
            "value": 38.0,
            "alert_type": "both"
        },
        {
            "timestamp": "2023-10-01 10:15:00",
            "user_id": hash_uid("patient_1"),
            "value": 160.0,
            "alert_type": "both"
        }
    ]

    for i, expected in enumerate(expected_fixed):
        actual = alerts[i]
        for key in ["timestamp", "user_id", "value", "alert_type"]:
            assert key in actual, f"Alert at index {i} is missing the '{key}' key."

        actual_ts_str = actual["timestamp"].replace("T", " ").replace("Z", "")
        expected_ts_str = expected["timestamp"]
        assert actual_ts_str == expected_ts_str, \
            f"Alert {i} timestamp mismatch: expected {expected_ts_str}, got {actual['timestamp']}."
        assert actual["user_id"] == expected["user_id"], \
            f"Alert {i} user_id mismatch: expected {expected['user_id']}, got {actual['user_id']}."
        assert float(actual["value"]) == expected["value"], \
            f"Alert {i} value mismatch: expected {expected['value']}, got {actual['value']}."
        assert actual["alert_type"] == expected["alert_type"], \
            f"Alert {i} alert_type mismatch: expected {expected['alert_type']}, got {actual['alert_type']}."

    # Independently derive and compare all alerts from the complete unified data.
    derived = expected_alerts()
    for i, expected in enumerate(derived):
        actual = alerts[i]
        assert canonical_timestamp(actual['timestamp']) == expected['timestamp']
        assert actual['user_id'] == expected['user_id']
        assert float(actual['value']) == expected['value']
        assert actual['alert_type'] == expected['alert_type']
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
