#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
from pathlib import Path

import pandas as pd
import pytest

PROJECT = Path('/home/user/etl_pipeline')
CSV_PATH = Path('/home/user/data/readings.csv')
JSON_PATH = Path('/home/user/anomalies.json')


def run_rust_pipeline():
    if JSON_PATH.exists():
        JSON_PATH.unlink()

    result = subprocess.run(
        ['cargo', 'run', '--release', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=str(PROJECT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert result.returncode == 0, f'Rust pipeline failed:\n{result.stdout}'
    assert JSON_PATH.is_file(), 'Rust pipeline did not create /home/user/anomalies.json'


def load_and_validate_output():
    try:
        with JSON_PATH.open('r') as f:
            values = json.load(f)
    except Exception as e:
        pytest.fail(f'Failed to read or parse {JSON_PATH}: {e}')

    assert isinstance(values, list), 'Output must be a single JSON array'
    assert all(type(value) is int for value in values), 'Every array element must be an integer row_id'
    assert values == sorted(values), 'Anomaly row_ids must be sorted in ascending order'
    return values


def test_rust_project_and_execution():
    assert PROJECT.is_dir(), f'Missing Rust project directory: {PROJECT}'
    assert (PROJECT / 'Cargo.toml').is_file(), 'Missing Cargo.toml in Rust project'
    rust_sources = [p for p in PROJECT.rglob('*.rs') if 'target' not in p.parts]
    assert rust_sources, 'Rust project contains no Rust source files'
    assert any(p.stat().st_size > 0 for p in rust_sources), 'Rust source files are empty'
    assert CSV_PATH.is_file(), f'Missing CSV file: {CSV_PATH}'

    build = subprocess.run(
        ['cargo', 'build', '--release', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=str(PROJECT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert build.returncode == 0, f'Rust project failed to build:\n{build.stdout}'

    original_csv = CSV_PATH.read_bytes()
    probe_csv = (
        'row_id,timestamp,sensor_name,value\n'
        '8,2023-01-01T00:00:00Z,Other_Sensor,99999\n'
        '2,2023-01-01T00:00:01Z,Pressure_Sensor,115.51\n'
        '7,2023-01-01T00:00:02Z,Pressure_Sensor,115.50\n'
        '1,2023-01-01T00:00:03Z,Pressure_Sensor,105.00\n'
        '5,2023-01-01T00:00:04Z,Temp_Sensor,301.26\n'
        '4,2023-01-01T00:00:05Z,Temp_Sensor,301.25\n'
        '3,2023-01-01T00:00:06Z,Temp_Sensor,298.50\n'
    ).encode()

    try:
        CSV_PATH.write_bytes(probe_csv)
        run_rust_pipeline()
        assert load_and_validate_output() == [2, 5], (
            'Rust pipeline produced incorrect results on verifier-generated input'
        )
    finally:
        CSV_PATH.write_bytes(original_csv)

    # Generate the required final artifact from the original dataset using Rust.
    run_rust_pipeline()


def test_anomaly_detection_f1_score():
    csv_path = '/home/user/data/readings.csv'
    json_path = '/home/user/anomalies.json'

    assert os.path.exists(csv_path), f"Missing CSV file: {csv_path}"
    assert os.path.exists(json_path), f"Missing JSON output file: {json_path}"

    # Load ground truth
    df = pd.read_csv(csv_path)
    anomalies = []
    for idx, row in df.iterrows():
        if row['sensor_name'] == 'Pressure_Sensor':
            if abs(row['value'] - 105.0) > 2.5 * 4.2:
                anomalies.append(int(row['row_id']))
        elif row['sensor_name'] == 'Temp_Sensor':
            if abs(row['value'] - 298.5) > 2.5 * 1.1:
                anomalies.append(int(row['row_id']))

    gt_set = set(anomalies)

    # Load agent output
    try:
        with open(json_path, 'r') as f:
            pred_list = json.load(f)
        assert isinstance(pred_list, list), 'Output must be a JSON array'
        assert all(type(value) is int for value in pred_list), 'Output values must be integers'
        assert pred_list == sorted(pred_list), 'Output row_ids must be sorted ascending'
        pred_set = set(pred_list)
    except Exception as e:
        pytest.fail(f"Failed to read or parse {json_path}: {e}")

    # Calculate F1
    tp = len(gt_set.intersection(pred_set))
    fp = len(pred_set - gt_set)
    fn = len(gt_set - pred_set)

    if tp == 0:
        f1 = 0.0
    else:
        precision = tp / (tp + fp)
        recall = tp / (tp + fn)
        f1 = 2 * (precision * recall) / (precision + recall)

    assert f1 >= 0.95, f"F1 Score {f1:.4f} is below threshold 0.95. TP: {tp}, FP: {fp}, FN: {fn}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
