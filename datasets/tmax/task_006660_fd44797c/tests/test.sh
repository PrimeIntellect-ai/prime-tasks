#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd

USERS_PATH = Path('/home/user/users.csv')
EVENTS_PATH = Path('/home/user/events.csv')
PARQUET_PATH = Path('/home/user/clean_data.parquet')
METRICS_PATH = Path('/home/user/metrics.json')

CANONICAL_USERS = pd.DataFrame({
    'user_id': [1, 2, 3, 4, 5, 6, 7],
    'account_tier': [1, 2, 1, 3, 2, 1, 3],
})
CANONICAL_EVENTS = pd.DataFrame({
    'user_id': [2, 3, 4, 5, 8, 9],
    'event_count': [10.0, 5.0, 20.0, 1.0, 100.0, 50.0],
    'event_value': [100.0, 50.0, 200.0, 10.0, 500.0, 250.0],
})


def expected_result(users, events):
    joined = users.merge(events, on='user_id', how='outer')
    total_rows = len(joined)
    cleaned = joined.dropna(subset=['account_tier']).copy()
    rows_dropped = total_rows - len(cleaned)
    cleaned['event_count'] = cleaned['event_count'].fillna(0.0)
    cleaned['event_value'] = cleaned['event_value'].fillna(0.0)
    cleaned['account_tier'] = cleaned['account_tier'].astype('int64')
    raw_activity = (
        cleaned['event_count'].to_numpy(dtype=float) * 0.4
        + cleaned['event_value'].to_numpy(dtype=float) * 0.6
    )
    outliers_capped = int(np.count_nonzero(raw_activity > 50.0))
    cleaned['activity_index'] = np.minimum(raw_activity, 50.0)
    metrics = {
        'total_rows_after_join': int(total_rows),
        'rows_dropped': int(rows_dropped),
        'outliers_capped': outliers_capped,
    }
    return cleaned, metrics


def validate_artifacts(expected_df, expected_metrics, canonical=False):
    assert METRICS_PATH.is_file(), f'Metrics file {METRICS_PATH} is missing.'
    try:
        with METRICS_PATH.open() as f:
            metrics = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'{METRICS_PATH} is not a valid JSON file.') from exc

    expected_keys = {'total_rows_after_join', 'rows_dropped', 'outliers_capped'}
    assert set(metrics.keys()) == expected_keys, (
        f'Metrics JSON must contain exactly keys: {expected_keys}'
    )
    assert all(type(metrics[k]) is int for k in expected_keys), 'All metrics must be JSON integers.'
    assert metrics == expected_metrics, f'Incorrect metrics: expected {expected_metrics}, got {metrics}'

    if canonical:
        assert metrics['total_rows_after_join'] == 9, (
            f"Expected 9 total_rows_after_join, got {metrics['total_rows_after_join']}"
        )
        assert metrics['rows_dropped'] == 2, (
            f"Expected 2 rows_dropped, got {metrics['rows_dropped']}"
        )
        assert metrics['outliers_capped'] == 2, (
            f"Expected 2 outliers_capped, got {metrics['outliers_capped']}"
        )

    assert PARQUET_PATH.is_file(), f'Output file {PARQUET_PATH} is missing.'
    try:
        actual = pd.read_parquet(PARQUET_PATH)
    except Exception as exc:
        raise AssertionError(f'Failed to read parquet: {exc}') from exc

    required_columns = {'user_id', 'account_tier', 'event_count', 'event_value', 'activity_index'}
    assert set(actual.columns) == required_columns, (
        f'Parquet must contain exactly {required_columns}; got {set(actual.columns)}'
    )
    assert actual.columns.is_unique, 'Parquet contains duplicate column names.'
    assert str(actual['account_tier'].dtype) in {'int32', 'int64'}, (
        f"account_tier must be int32 or int64, got {actual['account_tier'].dtype}"
    )
    assert not actual.isna().any().any(), 'Final dataset must not contain missing values.'
    assert len(actual) == len(expected_df), (
        f'Expected {len(expected_df)} rows in final dataset, got {len(actual)}'
    )
    assert actual['user_id'].is_unique, 'Final dataset contains duplicate user_id rows.'
    assert actual['activity_index'].max() <= 50.0, (
        f"activity_index was not capped properly. Max value: {actual['activity_index'].max()}"
    )

    columns = ['user_id', 'account_tier', 'event_count', 'event_value', 'activity_index']
    actual_sorted = actual[columns].sort_values('user_id').reset_index(drop=True)
    expected_sorted = expected_df[columns].sort_values('user_id').reset_index(drop=True)
    pd.testing.assert_frame_equal(
        actual_sorted,
        expected_sorted,
        check_dtype=False,
        check_exact=False,
        rtol=1e-10,
        atol=1e-10,
    )

    if canonical:
        assert len(actual) == 7, f'Expected 7 rows in final dataset, got {len(actual)}'
        expected_activity = {1: 0.0, 2: 50.0, 3: 32.0, 4: 50.0, 5: 6.4, 6: 0.0, 7: 0.0}
        for uid, expected_val in expected_activity.items():
            values = actual.loc[actual['user_id'] == uid, 'activity_index'].values
            assert len(values) == 1, f'Expected exactly one row for user {uid}.'
            assert abs(float(values[0]) - expected_val) <= 1e-5, (
                f'Incorrect activity_index for user {uid}: expected {expected_val}, got {values[0]}'
            )


def write_inputs(users, events):
    users.to_csv(USERS_PATH, index=False)
    events.to_csv(EVENTS_PATH, index=False)


def clear_outputs():
    for path in (PARQUET_PATH, METRICS_PATH):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def test_final_state_and_reproducible_pipeline():
    # Ensure the supplied source data was not replaced to manipulate derived expectations.
    current_users = pd.read_csv(USERS_PATH)
    current_events = pd.read_csv(EVENTS_PATH)
    pd.testing.assert_frame_equal(current_users, CANONICAL_USERS, check_dtype=False)
    pd.testing.assert_frame_equal(current_events, CANONICAL_EVENTS, check_dtype=False)

    canonical_expected, canonical_metrics = expected_result(CANONICAL_USERS, CANONICAL_EVENTS)
    validate_artifacts(canonical_expected, canonical_metrics, canonical=True)

    scripts = sorted(
        p for p in Path('/home/user').rglob('*.py')
        if p.is_file() and not p.is_symlink()
    )
    assert scripts, 'No Python preprocessing script was written under /home/user.'

    # Exercise the submitted script on an unseen outer-join case so a hardcoded
    # parquet/metrics pair cannot pass as an implementation of the pipeline.
    challenge_users = pd.DataFrame({
        'user_id': [101, 102, 103, 104],
        'account_tier': [4, 0, -2, 7],
    })
    challenge_events = pd.DataFrame({
        'user_id': [102, 103, 105, 106],
        'event_count': [5.0, 126.0, 1.0, -10.0],
        'event_value': [80.0, 0.0, 2.0, 100.0],
    })
    challenge_expected, challenge_metrics = expected_result(challenge_users, challenge_events)

    successful_script = None
    failures = []
    for script in scripts:
        write_inputs(challenge_users, challenge_events)
        clear_outputs()
        try:
            result = subprocess.run(
                ['python3', str(script)],
                cwd='/home/user',
                capture_output=True,
                text=True,
                timeout=30,
            )
            if result.returncode != 0:
                failures.append(f'{script}: exit {result.returncode}: {result.stderr[-500:]}')
                continue
            validate_artifacts(challenge_expected, challenge_metrics)
            successful_script = script
            break
        except Exception as exc:
            failures.append(f'{script}: {exc}')

    assert successful_script is not None, (
        'No submitted Python script reproduced the required pipeline on verification inputs. '
        + ' | '.join(failures)
    )

    # Restore the original inputs and require the same script to recreate the canonical outputs.
    write_inputs(CANONICAL_USERS, CANONICAL_EVENTS)
    clear_outputs()
    result = subprocess.run(
        ['python3', str(successful_script)],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'Script failed when rerun on original inputs:\n{result.stdout}\n{result.stderr}'
    )
    validate_artifacts(canonical_expected, canonical_metrics, canonical=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
