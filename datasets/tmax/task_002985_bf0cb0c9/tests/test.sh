#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import statistics
import time

import pytest

CLEANED_DATA_PATH = '/home/user/results/cleaned_data.csv'
SUMMARY_JSON_PATH = '/home/user/results/summary.json'
SENSORS_PATH = '/home/user/data/sensors.csv'
MAINTENANCE_PATH = '/home/user/data/maintenance.json'
EXPECTED_HEADER = ['machine_id', 'temperature', 'vibration', 'needs_repair']


def load_and_validate_cleaned_data():
    with open(SENSORS_PATH, newline='') as f:
        source_rows = list(csv.DictReader(f))
    with open(MAINTENANCE_PATH) as f:
        maintenance_rows = json.load(f)

    assert len(source_rows) == 500
    assert isinstance(maintenance_rows, list)

    source_by_id = {row['machine_id']: row for row in source_rows}
    maintenance_by_id = {row['machine_id']: row['needs_repair'] for row in maintenance_rows}
    assert len(source_by_id) == len(source_rows)
    assert len(maintenance_by_id) == len(maintenance_rows)

    with open(CLEANED_DATA_PATH, newline='') as f:
        reader = csv.reader(f, strict=True)
        parsed = list(reader)

    assert parsed, 'cleaned_data.csv is empty.'
    assert parsed[0] == EXPECTED_HEADER, f'Expected header {EXPECTED_HEADER}, got {parsed[0]}.'
    assert len(parsed) == 501, f'Expected one header and 500 CSV records, got {len(parsed)} total records.'
    assert all(len(row) == 4 for row in parsed[1:]), 'Every cleaned CSV record must have exactly four fields.'

    non_null_temperatures = {
        float(row['temperature']) for row in source_rows if row['temperature'] not in ('', None)
    }
    cleaned = []
    seen_ids = set()

    for record in parsed[1:]:
        machine_id, temperature_text, vibration_text, repair_text = record
        assert machine_id in source_by_id, f'Unknown machine_id {machine_id!r}.'
        assert machine_id not in seen_ids, f'Duplicate machine_id {machine_id!r}.'
        seen_ids.add(machine_id)

        assert temperature_text.strip() != '', f'Temperature was not imputed for {machine_id}.'
        try:
            temperature = float(temperature_text)
            vibration = float(vibration_text)
            needs_repair = int(repair_text)
        except ValueError as exc:
            pytest.fail(f'Non-numeric cleaned value for {machine_id}: {exc}')

        assert math.isfinite(temperature), f'Non-finite temperature for {machine_id}.'
        assert math.isfinite(vibration), f'Non-finite vibration for {machine_id}.'
        original = source_by_id[machine_id]
        assert vibration == float(original['vibration']), f'Vibration changed for {machine_id}.'
        assert needs_repair == maintenance_by_id[machine_id], f'Incorrect maintenance join for {machine_id}.'

        if original['temperature'] not in ('', None):
            assert temperature == float(original['temperature']), f'Non-null temperature changed for {machine_id}.'
        else:
            assert temperature in non_null_temperatures, (
                f'Imputed temperature for {machine_id} was not bootstrap-sampled from a non-null source value.'
            )

        cleaned.append((machine_id, temperature, vibration, needs_repair))

    assert seen_ids == set(source_by_id), 'Cleaned output does not contain exactly all sensor machine IDs.'
    assert seen_ids == set(maintenance_by_id), 'Cleaned output does not represent the complete merge.'
    return cleaned


def load_summary():
    with open(SUMMARY_JSON_PATH) as f:
        return json.load(f)


def test_cleaned_data_exists_and_has_correct_rows():
    """Verify that cleaned_data.csv exists and has exactly 501 lines (header + 500 rows)."""
    assert os.path.exists(CLEANED_DATA_PATH), f'Cleaned data CSV missing at {CLEANED_DATA_PATH}.'
    with open(CLEANED_DATA_PATH) as f:
        lines = f.readlines()
    assert len(lines) == 501, f'Expected 501 lines (1 header + 500 data rows), got {len(lines)}.'
    load_and_validate_cleaned_data()


def test_summary_json_exists_and_valid():
    """Verify that summary.json exists and is valid JSON."""
    assert os.path.exists(SUMMARY_JSON_PATH), f'Summary JSON missing at {SUMMARY_JSON_PATH}.'
    try:
        load_summary()
    except json.JSONDecodeError:
        pytest.fail(f'The file {SUMMARY_JSON_PATH} is not valid JSON.')


def test_summary_json_contents_and_recomputed_model_results():
    """Verify report fields against a freshly trained required model and benchmark."""
    summary = load_summary()
    expected_keys = {'num_rows_cleaned', 'model_accuracy', 'avg_inference_ms'}
    assert set(summary.keys()) == expected_keys, (
        f'summary.json keys mismatch. Expected {expected_keys}, got {set(summary.keys())}.'
    )

    assert summary['num_rows_cleaned'] == 500, (
        f"Expected num_rows_cleaned to be 500, got {summary['num_rows_cleaned']}."
    )

    accuracy = summary['model_accuracy']
    assert isinstance(accuracy, (int, float)), 'model_accuracy must be a number.'
    assert round(accuracy, 2) == 1.0, f'Expected model_accuracy ~1.0, got {accuracy}.'

    avg_inference_ms = summary['avg_inference_ms']
    assert isinstance(avg_inference_ms, float), (
        f'avg_inference_ms must be a float, got {type(avg_inference_ms).__name__}.'
    )
    assert math.isfinite(avg_inference_ms) and avg_inference_ms > 0.0, (
        f'avg_inference_ms must be finite and greater than 0, got {avg_inference_ms}.'
    )

    cleaned = load_and_validate_cleaned_data()
    X = [[row[1], row[2]] for row in cleaned]
    y = [row[3] for row in cleaned]

    try:
        from sklearn.ensemble import RandomForestClassifier
    except ImportError as exc:
        pytest.fail(f'scikit-learn is required to verify the requested Random Forest model: {exc}')

    model = RandomForestClassifier(random_state=42)
    model.fit(X, y)
    predictions = model.predict(X)
    recomputed_accuracy = sum(int(a == b) for a, b in zip(predictions, y)) / len(y)
    expected_accuracy = round(recomputed_accuracy, 2)
    assert accuracy == expected_accuracy, (
        f'Reported model_accuracy {accuracy} does not equal recomputed accuracy {expected_accuracy}.'
    )

    # Repeat the exact requested 100-pass benchmark and use the median of three
    # runs to reduce scheduler noise. The tolerance accommodates normal timing
    # variation while rejecting values unrelated to full-dataset prediction.
    measured_runs = []
    for _ in range(3):
        start = time.perf_counter()
        for _ in range(100):
            model.predict(X)
        measured_runs.append((time.perf_counter() - start) * 1000.0 / 100.0)
    measured_ms = statistics.median(measured_runs)
    tolerance = max(0.75, measured_ms * 0.60)
    assert abs(avg_inference_ms - measured_ms) <= tolerance, (
        f'Reported avg_inference_ms {avg_inference_ms:.6g} is inconsistent with the '
        f'recomputed 100-pass benchmark {measured_ms:.6g} ms.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
