#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
import statistics
import subprocess
import sys
import tempfile

import pandas as pd
import pytest
from sklearn.ensemble import RandomForestClassifier

PIPELINE = '/home/user/pipeline.py'
DATASET = '/home/user/dataset.csv'
RESULTS = '/home/user/results.json'


def object_signature(obj):
    if hasattr(obj, 'to_numpy'):
        values = obj.to_numpy()
    else:
        import numpy as np
        values = np.asarray(obj)
    payload = json.dumps(values.tolist(), separators=(',', ':'), allow_nan=True)
    return {
        'shape': list(values.shape),
        'hash': hashlib.sha256(payload.encode('utf-8')).hexdigest(),
        'columns': [str(c) for c in obj.columns] if hasattr(obj, 'columns') else None,
        'dtypes': [str(d) for d in obj.dtypes] if hasattr(obj, 'dtypes') else None,
    }


@pytest.fixture(scope='module')
def executed_pipeline():
    assert os.path.exists(PIPELINE), f'{PIPELINE} does not exist.'
    assert os.path.isfile(PIPELINE), f'{PIPELINE} is not a file.'
    assert os.path.exists(DATASET), f'Dataset file missing at {DATASET}'

    if os.path.lexists(RESULTS):
        os.remove(RESULTS)

    hook_dir = tempfile.mkdtemp(prefix='pipeline_hook_')
    telemetry_path = os.path.join(hook_dir, 'telemetry.json')
    hook = r'''
import functools
import hashlib
import json
import os
import numpy as np
import sklearn.ensemble._forest as _forest

_TELEMETRY = os.environ['PIPELINE_TELEMETRY']
_MODELS = []


def _safe(value):
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, (list, tuple)):
        return [_safe(v) for v in value]
    if isinstance(value, dict):
        return {str(k): _safe(v) for k, v in value.items()}
    return repr(value)


def _signature(obj):
    values = obj.to_numpy() if hasattr(obj, 'to_numpy') else np.asarray(obj)
    payload = json.dumps(values.tolist(), separators=(',', ':'), allow_nan=True)
    return {
        'shape': list(values.shape),
        'hash': hashlib.sha256(payload.encode('utf-8')).hexdigest(),
        'columns': [str(c) for c in obj.columns] if hasattr(obj, 'columns') else None,
        'dtypes': [str(d) for d in obj.dtypes] if hasattr(obj, 'dtypes') else None,
    }


def _flush():
    temporary = _TELEMETRY + '.tmp'
    with open(temporary, 'w') as f:
        json.dump({'models': _MODELS}, f)
    os.replace(temporary, _TELEMETRY)


_cls = _forest.RandomForestClassifier
_original_init = _cls.__init__
_original_fit = _cls.fit
_original_predict = _cls.predict


@functools.wraps(_original_init)
def _tracked_init(self, *args, **kwargs):
    _original_init(self, *args, **kwargs)
    record = {
        'object_id': id(self),
        'params': _safe(self.get_params(deep=False)),
        'fit': None,
        'predict_calls': [],
    }
    self._verifier_rf_record = record
    _MODELS.append(record)
    _flush()


@functools.wraps(_original_fit)
def _tracked_fit(self, X, y, *args, **kwargs):
    result = _original_fit(self, X, y, *args, **kwargs)
    record = getattr(self, '_verifier_rf_record', None)
    if record is not None:
        record['fit'] = {'X': _signature(X), 'y': _signature(y)}
        _flush()
    return result


@functools.wraps(_original_predict)
def _tracked_predict(self, X, *args, **kwargs):
    result = _original_predict(self, X, *args, **kwargs)
    record = getattr(self, '_verifier_rf_record', None)
    if record is not None:
        record['predict_calls'].append(_signature(X))
        _flush()
    return result


_cls.__init__ = _tracked_init
_cls.fit = _tracked_fit
_cls.predict = _tracked_predict
'''
    with open(os.path.join(hook_dir, 'sitecustomize.py'), 'w') as f:
        f.write(hook)

    env = os.environ.copy()
    env['PIPELINE_TELEMETRY'] = telemetry_path
    env['PYTHONPATH'] = hook_dir + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    completed = subprocess.run(
        [sys.executable, PIPELINE],
        cwd='/home/user',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert completed.returncode == 0, (
        f'pipeline.py failed with exit code {completed.returncode}\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )
    assert os.path.isfile(telemetry_path), 'No RandomForestClassifier activity was observed.'
    with open(telemetry_path) as f:
        telemetry = json.load(f)
    return telemetry


def expected_clean_data():
    frame = pd.read_csv(DATASET)
    numeric_a = pd.to_numeric(frame['feature_A'].replace('MISSING', pd.NA), errors='coerce')
    median_a = int(numeric_a.dropna().median())
    frame['feature_A'] = numeric_a.fillna(median_a).astype('int64')
    return frame, median_a


def test_pipeline_trained_and_benchmarked_random_forest(executed_pipeline):
    frame, _ = expected_clean_data()
    expected_X = frame[['feature_A', 'feature_B']]
    expected_y = frame['label']
    expected_x_signature = object_signature(expected_X)
    expected_y_signature = object_signature(expected_y)

    expected_params = RandomForestClassifier().get_params(deep=False)
    expected_params['random_state'] = 42

    qualifying = []
    for model in executed_pipeline.get('models', []):
        if model.get('params') != expected_params:
            continue
        fit = model.get('fit')
        if not fit or fit.get('X') != expected_x_signature or fit.get('y') != expected_y_signature:
            continue
        calls = model.get('predict_calls', [])
        if len(calls) >= 100 and all(call == expected_x_signature for call in calls):
            qualifying.append(model)

    assert qualifying, (
        'pipeline.py must fit RandomForestClassifier(random_state=42) with all other '
        'parameters at their defaults on the cleaned feature_A/feature_B data, and '
        'must call predict(X) at least 100 times on the training features.'
    )


def test_results_json_exists(executed_pipeline):
    assert os.path.exists(RESULTS), '/home/user/results.json does not exist.'
    assert os.path.isfile(RESULTS), '/home/user/results.json is not a file.'


def test_results_json_content(executed_pipeline):
    with open(RESULTS, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('/home/user/results.json is not valid JSON.')

    with open(DATASET, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        vals = []
        for row in reader:
            val = row.get('feature_A')
            if val != 'MISSING' and val is not None:
                vals.append(int(val))
    expected_median = int(statistics.median(vals))

    assert 'median_A' in data, "Key 'median_A' missing in results.json"
    assert data['median_A'] == expected_median, f"Expected 'median_A' to be {expected_median}, got {data['median_A']}"

    assert 'feature_A_dtype' in data, "Key 'feature_A_dtype' missing in results.json"
    assert data['feature_A_dtype'] == 'int64', f"Expected 'feature_A_dtype' to be 'int64', got {data['feature_A_dtype']}"

    assert 'accuracy' in data, "Key 'accuracy' missing in results.json"
    assert isinstance(data['accuracy'], (int, float)), "Key 'accuracy' must be a float"
    assert float(data['accuracy']) == 1.0, f"Expected 'accuracy' to be 1.0, got {data['accuracy']}"

    assert 'inference_time_sec' in data, "Key 'inference_time_sec' missing in results.json"
    assert isinstance(data['inference_time_sec'], (int, float)), "Key 'inference_time_sec' must be a float"
    assert float(data['inference_time_sec']) > 0, "Expected 'inference_time_sec' to be greater than 0"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
