#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import math
import pandas as pd
import pytest

RAW_DATA_DIR = "/home/user/raw_data"
OUTPUT_DIR = "/home/user/output"
REJECTED_LOG = os.path.join(OUTPUT_DIR, "rejected.log")
CLEANED_DIR = os.path.join(OUTPUT_DIR, "cleaned")
SIMILAR_JSON = os.path.join(OUTPUT_DIR, "similar_sensors.json")


def get_sensor_data():
    """Reads all sensor data from raw_data and returns a dictionary of sensor_id -> data."""
    sensors = {}
    if not os.path.exists(RAW_DATA_DIR):
        return sensors

    for filename in os.listdir(RAW_DATA_DIR):
        if filename.endswith(".csv") and filename.startswith("sensor_"):
            filepath = os.path.join(RAW_DATA_DIR, filename)
            sensor_id = filename.replace(".csv", "")

            data = []
            with open(filepath, 'r', newline='') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    data.append(row)
            sensors[sensor_id] = {'filename': filename, 'data': data}
    return sensors


def compute_missing_stats(data):
    total = len(data)
    missing = sum(1 for row in data if not row['temperature'].strip())
    return missing / total if total > 0 else 0


def impute_temperature(data):
    """Imputes missing temperature values using linear interpolation, then bfill/ffill."""
    temps = []
    for row in data:
        val = row['temperature'].strip()
        temps.append(float(val) if val else None)

    # Linear interpolation
    for i in range(len(temps)):
        if temps[i] is None:
            prev_idx = i - 1
            while prev_idx >= 0 and temps[prev_idx] is None:
                prev_idx -= 1

            next_idx = i + 1
            while next_idx < len(temps) and temps[next_idx] is None:
                next_idx += 1

            if prev_idx >= 0 and next_idx < len(temps):
                prev_val = temps[prev_idx]
                next_val = temps[next_idx]
                temps[i] = prev_val + (next_val - prev_val) * (i - prev_idx) / (next_idx - prev_idx)

    # bfill
    for i in range(len(temps)):
        if temps[i] is None:
            next_idx = i + 1
            while next_idx < len(temps) and temps[next_idx] is None:
                next_idx += 1
            if next_idx < len(temps):
                temps[i] = temps[next_idx]

    # ffill
    for i in range(len(temps)):
        if temps[i] is None:
            prev_idx = i - 1
            if prev_idx >= 0:
                temps[i] = temps[prev_idx]

    return temps


def euclidean_distance(v1, v2):
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(v1, v2)))


@pytest.fixture(scope="module")
def expected_state():
    sensors = get_sensor_data()
    rejected = []
    valid_sensors = {}
    valid_frames = {}

    for sensor_id, s_info in sensors.items():
        missing_rate = compute_missing_stats(s_info['data'])
        if missing_rate > 0.30:
            rejected.append(s_info['filename'])
        else:
            # Sort chronologically by timestamp
            sorted_data = sorted(s_info['data'], key=lambda x: float(x['timestamp']))
            imputed_temps = impute_temperature(sorted_data)
            valid_sensors[sensor_id] = imputed_temps

            expected_df = pd.DataFrame(
                sorted_data,
                columns=['timestamp', 'temperature', 'moisture']
            )
            expected_df['timestamp'] = pd.to_numeric(expected_df['timestamp'])
            expected_df['temperature'] = imputed_temps
            expected_df['moisture'] = pd.to_numeric(expected_df['moisture'])
            valid_frames[sensor_id] = expected_df.reset_index(drop=True)

    rejected.sort()

    similar_pairs = []
    valid_ids = sorted(valid_sensors.keys())
    for i in range(len(valid_ids)):
        for j in range(i + 1, len(valid_ids)):
            id1 = valid_ids[i]
            id2 = valid_ids[j]
            dist = euclidean_distance(valid_sensors[id1], valid_sensors[id2])
            if dist < 15.0:
                pair = sorted([id1, id2])
                similar_pairs.append(pair)

    similar_pairs.sort(key=lambda x: x[0])

    return {
        'rejected': rejected,
        'valid_ids': valid_ids,
        'valid_frames': valid_frames,
        'similar_pairs': similar_pairs
    }


def test_rejected_log(expected_state):
    """Validate that the rejected.log contains exactly the expected filenames."""
    assert os.path.exists(REJECTED_LOG), f"Rejected log file not found at {REJECTED_LOG}"

    with open(REJECTED_LOG, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert sorted(lines) == expected_state['rejected'], (
        f"Rejected log contents incorrect. Expected {expected_state['rejected']}, got {sorted(lines)}"
    )


def test_cleaned_parquets(expected_state):
    """Validate that parquet files exist and contain the required cleaned DataFrames."""
    assert os.path.exists(CLEANED_DIR), f"Cleaned directory not found at {CLEANED_DIR}"

    actual_files = [f for f in os.listdir(CLEANED_DIR) if f.endswith('.parquet')]
    actual_ids = sorted([f.replace('.parquet', '') for f in actual_files])

    expected_ids = expected_state['valid_ids']
    assert actual_ids == expected_ids, (
        f"Cleaned parquet files incorrect. Expected sensors {expected_ids}, got {actual_ids}"
    )

    for sensor_id in expected_ids:
        path = os.path.join(CLEANED_DIR, sensor_id + '.parquet')
        assert os.path.isfile(path), f"Cleaned parquet is not a regular file: {path}"
        try:
            actual_df = pd.read_parquet(path)
        except Exception as exc:
            pytest.fail(f"Could not read {path} as parquet: {exc}")

        expected_df = expected_state['valid_frames'][sensor_id]
        assert list(actual_df.columns) == list(expected_df.columns), (
            f"Columns in {path} are incorrect. Expected {list(expected_df.columns)}, "
            f"got {list(actual_df.columns)}"
        )
        assert not actual_df['temperature'].isna().any(), (
            f"Temperature column in {path} still contains missing values"
        )
        assert actual_df['timestamp'].is_monotonic_increasing, (
            f"Rows in {path} are not sorted chronologically"
        )
        pd.testing.assert_frame_equal(
            actual_df.reset_index(drop=True),
            expected_df,
            check_dtype=False,
            check_exact=False,
            rtol=1e-10,
            atol=1e-10,
            obj=path
        )


def test_similar_sensors_json(expected_state):
    """Validate that similar_sensors.json contains the correct pairs."""
    assert os.path.exists(SIMILAR_JSON), f"Similar sensors JSON not found at {SIMILAR_JSON}"

    with open(SIMILAR_JSON, 'r') as f:
        try:
            actual_pairs = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("similar_sensors.json is not a valid JSON file.")

    normalized_actual = sorted([sorted(pair) for pair in actual_pairs], key=lambda x: x[0])

    assert normalized_actual == expected_state['similar_pairs'], (
        f"Similar sensors JSON contents incorrect. Expected {expected_state['similar_pairs']}, got {normalized_actual}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
