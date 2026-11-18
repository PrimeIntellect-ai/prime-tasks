#!/bin/bash
set -e
mkdir -p /logs/verifier

HOOK_DIR=$(mktemp -d)
cat << 'HOOK_EOF' > "$HOOK_DIR/sitecustomize.py"
import os
import numpy as np
from sklearn.linear_model import LinearRegression

_event_path = os.environ.get('VERIFIER_EVENT_PATH')
_original_seterr = np.seterr
_original_fit = LinearRegression.fit

def _record(event):
    if _event_path:
        with open(_event_path, 'a') as f:
            f.write(event + '\n')

def _tracked_seterr(*args, **kwargs):
    if kwargs.get('divide') == 'raise' and kwargs.get('invalid') == 'raise':
        _record('S')
    return _original_seterr(*args, **kwargs)

def _tracked_fit(self, *args, **kwargs):
    _record('F')
    return _original_fit(self, *args, **kwargs)

np.seterr = _tracked_seterr
LinearRegression.fit = _tracked_fit
HOOK_EOF

export VERIFIER_HOOK_DIR="$HOOK_DIR"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import subprocess

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import LinearRegression

SCRIPT_PATH = '/home/user/clean_and_test.py'
LOG_PATH = '/home/user/experiment_log.json'
DATA_PATH = '/home/user/data/raw_data.csv'
HOOK_DIR = os.environ['VERIFIER_HOOK_DIR']
EVENT_PATH = '/tmp/clean_and_test_events.log'


def expected_results(df):
    model = LinearRegression()
    model.fit(df[['featureA', 'featureB']], df['target'])
    errors = np.abs(df['target'].to_numpy() - model.predict(df[['featureA', 'featureB']]))
    positions = np.argsort(errors)[-3:]
    ids = sorted(int(df.iloc[position]['id']) for position in positions)
    return {
        'top_3_outlier_ids': ids,
        'mean_absolute_error': round(float(np.mean(errors)), 4),
    }


def run_submission():
    if os.path.exists(EVENT_PATH):
        os.remove(EVENT_PATH)

    env = os.environ.copy()
    old_pythonpath = env.get('PYTHONPATH', '')
    env['PYTHONPATH'] = HOOK_DIR + (os.pathsep + old_pythonpath if old_pythonpath else '')
    env['VERIFIER_EVENT_PATH'] = EVENT_PATH

    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f'{SCRIPT_PATH} did not run successfully.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )

    events = []
    if os.path.isfile(EVENT_PATH):
        with open(EVENT_PATH) as f:
            events = [line.strip() for line in f if line.strip()]
    assert 'S' in events, "The script did not call np.seterr(divide='raise', invalid='raise')."
    assert 'F' in events, 'The script did not fit sklearn.linear_model.LinearRegression.'
    assert events.index('S') < events.index('F'), 'np.seterr must be configured before fitting the model.'

    assert os.path.isfile(LOG_PATH), f'Experiment log file is missing at {LOG_PATH}'
    with open(LOG_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {LOG_PATH} is not valid JSON.')


def assert_schema_and_values(data, expected):
    assert set(data.keys()) == {'top_3_outlier_ids', 'mean_absolute_error'}, 'JSON schema is incorrect.'
    assert isinstance(data['top_3_outlier_ids'], list), 'top_3_outlier_ids must be a list.'
    assert data['top_3_outlier_ids'] == sorted(data['top_3_outlier_ids']), 'Outlier IDs must be ascending.'
    assert type(data['mean_absolute_error']) is float, 'mean_absolute_error must be a float.'
    assert data['top_3_outlier_ids'] == expected['top_3_outlier_ids']
    assert data['mean_absolute_error'] == expected['mean_absolute_error']


def test_script_exists_and_is_python():
    assert os.path.isfile(SCRIPT_PATH), f'Python script is missing at {SCRIPT_PATH}'
    with open(SCRIPT_PATH, 'r') as f:
        source = f.read()
    try:
        ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f'{SCRIPT_PATH} is not valid Python: {exc}')


def test_experiment_log_exists_and_content_is_recomputed():
    original_df = pd.read_csv(DATA_PATH)
    expected = expected_results(original_df)
    data = run_submission()

    # Preserve the original verifier's assertions.
    assert 'top_3_outlier_ids' in data, "Key 'top_3_outlier_ids' is missing from the JSON file."
    assert 'mean_absolute_error' in data, "Key 'mean_absolute_error' is missing from the JSON file."
    expected_outliers = [13, 46, 89]
    assert data['top_3_outlier_ids'] == expected_outliers, \
        f"Expected top_3_outlier_ids to be {expected_outliers}, but got {data['top_3_outlier_ids']}"
    expected_mae = 1.5583
    actual_mae = data['mean_absolute_error']
    assert isinstance(actual_mae, (int, float)), 'mean_absolute_error must be a number.'
    assert abs(actual_mae - expected_mae) <= 0.0001, \
        f'Expected mean_absolute_error to be approximately {expected_mae}, but got {actual_mae}'

    assert_schema_and_values(data, expected)


def test_script_processes_changed_input():
    with open(DATA_PATH, 'rb') as f:
        original_bytes = f.read()

    changed = pd.DataFrame({
        'id': [201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212],
        'featureA': [0.2, 1.1, 2.4, 3.0, 4.8, 5.2, 6.7, 7.3, 8.9, 9.4, 10.6, 11.8],
        'featureB': [4.1, 0.3, 3.7, 1.2, 4.8, 2.0, 0.7, 3.1, 1.8, 4.4, 2.6, 0.1],
        'target': [2.50, 3.38, 6.72, 14.61, 11.97, 12.15, 8.03, 16.17, 20.13, 24.61, 23.55, 27.64],
    })
    expected_changed = expected_results(changed)

    try:
        changed.to_csv(DATA_PATH, index=False)
        changed_data = run_submission()
        assert_schema_and_values(changed_data, expected_changed)
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_bytes)
        # Restore the requested final artifact using the original dataset.
        run_submission()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

rm -rf "$HOOK_DIR"
