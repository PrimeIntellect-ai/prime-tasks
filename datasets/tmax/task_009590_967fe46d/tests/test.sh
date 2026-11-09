#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

import numpy as np
import pandas as pd
from pandas.api.types import is_datetime64_any_dtype, is_float_dtype, is_string_dtype

DATA_PATH = Path('/home/user/data/telemetry.jsonl')
PARQUET_PATH = Path('/home/user/anomalies.parquet')
HOME = Path('/home/user')


def expected_from_jsonl(source):
    raw = pd.read_json(io.StringIO(source), lines=True)
    raw['ts'] = pd.to_datetime(raw['ts'], utc=True, errors='raise')
    raw['hour'] = raw['ts'].dt.floor('h')
    hourly = (
        raw.groupby(['device', 'hour'], as_index=False, sort=False)['val']
        .mean()
        .rename(columns={'val': 'mean_val'})
        .sort_values(['device', 'hour'])
        .reset_index(drop=True)
    )
    hourly['rolling_avg'] = hourly.groupby('device', sort=False)['mean_val'].transform(
        lambda values: values.rolling(window=3, min_periods=1).mean()
    )
    return hourly.loc[
        (hourly['mean_val'] - hourly['rolling_avg']).abs() > 5.0,
        ['device', 'hour', 'mean_val', 'rolling_avg'],
    ].reset_index(drop=True)


def read_and_validate_output(source):
    assert PARQUET_PATH.exists(), f'Expected output file {PARQUET_PATH} does not exist.'
    try:
        actual = pd.read_parquet(PARQUET_PATH)
    except Exception as exc:
        raise AssertionError(f'Failed to read {PARQUET_PATH} as a Parquet file: {exc}') from exc

    expected_columns = {'device', 'hour', 'mean_val', 'rolling_avg'}
    actual_columns = set(actual.columns)
    # Retain the original missing-column assertion and additionally reject extras.
    assert expected_columns.issubset(actual_columns), (
        f'Missing columns in output. Expected {expected_columns}, got {actual_columns}'
    )
    assert actual_columns == expected_columns, (
        f'Output must contain exactly {expected_columns}, got {actual_columns}'
    )

    assert is_string_dtype(actual['device'].dtype), (
        f'device must have a string-compatible dtype, got {actual["device"].dtype}'
    )
    assert actual['device'].map(lambda value: isinstance(value, str)).all(), (
        'Every device value must be a string.'
    )
    assert is_datetime64_any_dtype(actual['hour'].dtype), (
        f'hour must have a datetime dtype, got {actual["hour"].dtype}'
    )
    assert is_float_dtype(actual['mean_val'].dtype), (
        f'mean_val must have a float dtype, got {actual["mean_val"].dtype}'
    )
    assert is_float_dtype(actual['rolling_avg'].dtype), (
        f'rolling_avg must have a float dtype, got {actual["rolling_avg"].dtype}'
    )

    expected = expected_from_jsonl(source)
    assert len(actual) == len(expected), (
        f'Expected exactly {len(expected)} anomalies, but found {len(actual)}.'
    )

    actual_cmp = actual.copy()
    expected_cmp = expected.copy()
    actual_cmp['hour'] = pd.to_datetime(actual_cmp['hour'], utc=True, errors='raise')
    expected_cmp['hour'] = pd.to_datetime(expected_cmp['hour'], utc=True, errors='raise')
    actual_cmp = actual_cmp.sort_values(['device', 'hour']).reset_index(drop=True)
    expected_cmp = expected_cmp.sort_values(['device', 'hour']).reset_index(drop=True)

    assert actual_cmp['device'].tolist() == expected_cmp['device'].tolist(), (
        f'Incorrect anomaly devices: expected {expected_cmp["device"].tolist()}, '
        f'got {actual_cmp["device"].tolist()}'
    )
    assert actual_cmp['hour'].tolist() == expected_cmp['hour'].tolist(), (
        f'Incorrect anomaly hours: expected {expected_cmp["hour"].tolist()}, '
        f'got {actual_cmp["hour"].tolist()}'
    )
    np.testing.assert_allclose(
        actual_cmp['mean_val'].to_numpy(), expected_cmp['mean_val'].to_numpy(),
        rtol=1e-10, atol=1e-10, err_msg='Incorrect hourly mean values'
    )
    np.testing.assert_allclose(
        actual_cmp['rolling_avg'].to_numpy(), expected_cmp['rolling_avg'].to_numpy(),
        rtol=1e-10, atol=1e-10, err_msg='Incorrect rolling averages'
    )
    return actual


def run_script(script, source):
    DATA_PATH.write_text(source)
    PARQUET_PATH.unlink(missing_ok=True)
    result = subprocess.run(
        [sys.executable, str(script)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'{script} did not run successfully (exit {result.returncode}).\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    return read_and_validate_output(source)


def make_probe_data():
    suffix = secrets.token_hex(5)
    day = 2 + secrets.randbelow(20)
    shift = secrets.randbelow(41) - 20
    a = f'probe_alpha_{suffix}'
    b = f'probe_beta_{suffix}'
    c = f'probe_threshold_{suffix}'
    date = f'2024-11-{day:02d}'
    rows = [
        {'ts': f'{date}T15:47:00Z', 'device': a, 'val': 30 + shift},
        {'ts': f'{date}T09:52:00Z', 'device': a, 'val': 14 + shift},
        {'ts': f'{date}T16:03:00Z', 'device': a, 'val': 0 + shift},
        {'ts': f'{date}T11:11:00Z', 'device': a, 'val': 12 + shift},
        {'ts': f'{date}T09:04:00Z', 'device': a, 'val': 10 + shift},
        {'ts': f'{date}T12:27:00Z', 'device': b, 'val': 10 + shift},
        {'ts': f'{date}T08:33:00Z', 'device': b, 'val': 5 + shift},
        {'ts': f'{date}T13:02:00Z', 'device': b, 'val': 30 + shift},
        {'ts': f'{date}T09:15:00Z', 'device': b, 'val': 20 + shift},
        {'ts': f'{date}T10:05:00Z', 'device': c, 'val': 0 + shift},
        {'ts': f'{date}T11:55:00Z', 'device': c, 'val': 10 + shift},
    ]
    secrets.SystemRandom().shuffle(rows)
    return ''.join(json.dumps(row) + '\n' for row in rows)


def test_script_and_anomalies_parquet():
    original = DATA_PATH.read_text()
    ignored_parts = {'.cache', '.local', '.venv', 'venv', '__pycache__'}
    candidates = sorted(
        path for path in HOME.rglob('*.py')
        if path.is_file() and not path.is_symlink()
        and not any(part in ignored_parts for part in path.parts)
    )
    assert candidates, 'No Python processing script was found under /home/user.'

    selected = None
    failures = []
    original_df = None
    for script in candidates:
        try:
            original_df = run_script(script, original)
            selected = script
            break
        except Exception as exc:
            failures.append(f'{script}: {exc}')

    assert selected is not None, (
        'No submitted Python script successfully generated the required Parquet output.\n'
        + '\n'.join(failures)
    )

    # Retain the original dataset-specific assertions, now applied to freshly
    # generated output rather than a pre-existing artifact.
    assert len(original_df) == 2, f'Expected exactly 2 anomalies, but found {len(original_df)}.'
    a_anom = original_df[original_df['device'] == 'sensor_A']
    assert len(a_anom) == 1, 'Expected exactly 1 anomaly for sensor_A.'
    a_row = a_anom.iloc[0]
    assert pd.to_datetime(a_row['hour'], utc=True) == pd.Timestamp('2023-10-01T13:00:00Z')
    assert abs(a_row['mean_val'] - 34.5) < 0.1, f'Expected sensor_A mean_val around 34.5, got {a_row["mean_val"]}'
    assert abs(a_row['rolling_avg'] - 25.833) < 0.1, f'Expected sensor_A rolling_avg around 25.83, got {a_row["rolling_avg"]}'

    b_anom = original_df[original_df['device'] == 'sensor_B']
    assert len(b_anom) == 1, 'Expected exactly 1 anomaly for sensor_B.'
    b_row = b_anom.iloc[0]
    assert pd.to_datetime(b_row['hour'], utc=True) == pd.Timestamp('2023-10-01T13:00:00Z')
    assert abs(b_row['mean_val'] - 5.0) < 0.1, f'Expected sensor_B mean_val around 5.0, got {b_row["mean_val"]}'
    assert abs(b_row['rolling_avg'] - 12.333) < 0.1, f'Expected sensor_B rolling_avg around 12.33, got {b_row["rolling_avg"]}'

    try:
        run_script(selected, make_probe_data())
    finally:
        # Leave the supplied dataset restored and regenerate the requested final artifact.
        DATA_PATH.write_text(original)
        PARQUET_PATH.unlink(missing_ok=True)
        subprocess.run(
            [sys.executable, str(selected)], cwd='/home/user',
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        DATA_PATH.write_text(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
