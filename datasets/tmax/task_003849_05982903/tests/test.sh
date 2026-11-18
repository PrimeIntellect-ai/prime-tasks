#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pandas as pd
import numpy as np
import pytest

ORACLE_PATH = '/tests/ground_truth.csv'
assert os.path.isfile(ORACLE_PATH), f'Hidden ground truth {ORACLE_PATH} is missing.'
try:
    GT = pd.read_csv(ORACLE_PATH)
finally:
    os.remove(ORACLE_PATH)

PIPELINE = '/home/user/pipeline'
PRED_PATH = '/home/user/final_output.csv'
_RAN = False


def run_pipeline_once():
    global _RAN
    if _RAN:
        return

    required = [
        f'{PIPELINE}/process_log.awk',
        f'{PIPELINE}/parse_timestamps.sh',
        f'{PIPELINE}/calibrate.sh',
        f'{PIPELINE}/aggregate_queries.sh',
        f'{PIPELINE}/run_all.sh',
    ]
    for path in required:
        assert os.path.isfile(path), f'Required pipeline artifact {path} is missing.'
        assert os.path.getsize(path) > 0, f'Required pipeline artifact {path} is empty.'

    for path in [
        PRED_PATH,
        f'{PIPELINE}/timestamps.txt',
        f'{PIPELINE}/threshold.txt',
        f'{PIPELINE}/query_results.txt',
    ]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    subprocess.run(
        ['bash', f'{PIPELINE}/parse_timestamps.sh'],
        check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True,
    )
    timestamp_path = f'{PIPELINE}/timestamps.txt'
    assert os.path.isfile(timestamp_path), 'parse_timestamps.sh did not create timestamps.txt.'
    with open(timestamp_path) as f:
        parsed = [line.strip() for line in f if line.strip()]
    assert len(parsed) == 300, f'Expected 300 clean timestamps, got {len(parsed)}.'
    try:
        parsed_values = np.asarray([float(x) for x in parsed], dtype=float)
    except ValueError as e:
        pytest.fail(f'timestamps.txt contains a non-numeric value: {e}')
    assert np.isfinite(parsed_values).all(), 'timestamps.txt contains NaN or infinite values.'

    probe = subprocess.run(
        ['ffprobe', '-v', 'error', '-show_entries', 'packet=pts_time',
         '-of', 'csv=p=0', '/app/test_run.mp4'],
        check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True,
    )
    expected_pts = np.asarray(
        [float(x.strip()) for x in probe.stdout.splitlines() if x.strip()], dtype=float
    )
    assert len(expected_pts) == len(parsed_values), 'Parsed timestamp count differs from ffprobe output.'
    assert np.allclose(np.sort(parsed_values), np.sort(expected_pts), atol=1e-6, rtol=0), \
        'timestamps.txt does not contain the video packet timestamps.'

    subprocess.run(
        ['bash', f'{PIPELINE}/calibrate.sh'],
        check=True, timeout=10, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True,
    )
    threshold_path = f'{PIPELINE}/threshold.txt'
    assert os.path.isfile(threshold_path), 'calibrate.sh did not create threshold.txt.'
    with open(threshold_path) as f:
        threshold_text = f.read().strip()
    assert threshold_text == '128', f'Calibration produced threshold {threshold_text!r}, expected 128.'

    subprocess.run(
        ['bash', f'{PIPELINE}/aggregate_queries.sh'],
        check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True,
    )
    query_path = f'{PIPELINE}/query_results.txt'
    assert os.path.isfile(query_path), 'aggregate_queries.sh did not create query_results.txt.'
    query = pd.read_csv(
        query_path, sep='|', header=None,
        names=['frame_index', 'timestamp', 'calibrated_threshold', 'event_count'],
    )
    assert len(query) == len(GT), 'Aggregate query returned the wrong number of frames.'
    assert np.array_equal(query['frame_index'].to_numpy(), GT['frame_index'].to_numpy()), \
        'Aggregate query returned incorrect frame indices.'
    assert np.allclose(query['timestamp'], GT['timestamp'], atol=5e-4, rtol=0), \
        'Aggregate query returned incorrect timestamps.'
    assert np.array_equal(query['event_count'].to_numpy(), GT['event_count'].to_numpy()), \
        'Aggregate query returned incorrect event counts.'

    for path in [PRED_PATH, timestamp_path, threshold_path, query_path]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    subprocess.run(
        ['bash', f'{PIPELINE}/run_all.sh'],
        check=True, timeout=60, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True,
    )
    _RAN = True


def test_final_output_exists():
    run_pipeline_once()
    assert os.path.isfile(PRED_PATH), f'The final output file {PRED_PATH} was not generated.'


def test_metrics_threshold():
    run_pipeline_once()
    assert os.path.isfile(PRED_PATH), f'Prediction file {PRED_PATH} is missing.'

    try:
        pred = pd.read_csv(PRED_PATH)
    except Exception as e:
        pytest.fail(f'Failed to read prediction CSV: {e}')

    expected_columns = ['frame_index', 'timestamp', 'calibrated_threshold', 'event_count']
    assert list(pred.columns) == expected_columns, \
        f'Expected columns {expected_columns}, got {list(pred.columns)}.'
    assert len(GT) == len(pred), \
        f'Length mismatch: Expected {len(GT)} rows, but got {len(pred)} rows in final_output.csv.'
    assert 'calibrated_threshold' in pred.columns, \
        "Column 'calibrated_threshold' missing in final_output.csv."
    assert 'event_count' in pred.columns, "Column 'event_count' missing in final_output.csv."

    for column in expected_columns:
        assert pd.api.types.is_numeric_dtype(pred[column]), f'Column {column} must be numeric.'
        assert np.isfinite(pred[column].to_numpy(dtype=float)).all(), \
            f'Column {column} contains NaN or infinite values.'

    assert np.array_equal(pred['frame_index'].to_numpy(), GT['frame_index'].to_numpy()), \
        'frame_index values are incorrect or out of order.'
    assert np.allclose(pred['timestamp'], GT['timestamp'], atol=5e-4, rtol=0), \
        'timestamp values do not match the expected frames.'

    mse_threshold = np.mean((GT['calibrated_threshold'] - pred['calibrated_threshold']) ** 2)
    acc_events = np.mean(GT['event_count'] == pred['event_count'])

    assert mse_threshold <= 2.0, \
        f'MSE for calibrated_threshold is {mse_threshold:.3f}, which is > 2.0 threshold.'
    assert acc_events >= 0.95, \
        f'Event count accuracy is {acc_events:.3f}, which is < 0.95 threshold.'


def test_recovered_script_exists():
    run_pipeline_once()
    script_path = f'{PIPELINE}/process_log.awk'
    assert os.path.isfile(script_path), f'The deleted script was not recovered to {script_path}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
