#!/bin/bash
set -e
mkdir -p /logs/verifier

REPORT_PATH=/home/user/report.json
TELEMETRY_PATH=/tmp/model_task_telemetry.json
EXECUTION_FAILURE=/tmp/model_task_execution_failed
rm -f "$REPORT_PATH" "$TELEMETRY_PATH" "$EXECUTION_FAILURE"

# Locate the Python artifact requested by the instruction. Prefer files that
# mention the required inputs and APIs, while allowing any filename.
SCRIPT_PATH=$(python3 - <<'PY'
import os

candidates = []
for root, dirs, files in os.walk('/home/user'):
    dirs[:] = [d for d in dirs if not d.startswith('.') and d not in {'__pycache__', 'site-packages'}]
    for name in files:
        if not name.endswith('.py'):
            continue
        path = os.path.join(root, name)
        try:
            with open(path, 'r', errors='ignore') as f:
                text = f.read()
            score = sum(token in text for token in (
                'data.csv', 'report.json', 'GridSearchCV',
                'RandomForestClassifier', 'train_test_split', 'predict'
            ))
            candidates.append((score, os.path.getmtime(path), path))
        except OSError:
            pass

if candidates:
    candidates.sort(reverse=True)
    print(candidates[0][2])
PY
)

# Instrument execution so the verifier can establish that the submitted script
# actually performs the required grid search and 100 full-test-set predictions.
# The fixed delay also makes the reported timing independently testable.
mkdir -p /tmp/verifier_instrument
cat <<'PY' > /tmp/verifier_instrument/sitecustomize.py
import atexit
import json
import os
import time

TELEMETRY_PATH = '/tmp/model_task_telemetry.json'
PREDICT_DELAY_SECONDS = 0.015
telemetry = {'grid_searches': [], 'predictions': [], 'predict_delay_ms': 15.0}

try:
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.model_selection import GridSearchCV

    original_predict = RandomForestClassifier.predict
    original_grid_fit = GridSearchCV.fit

    def instrumented_predict(self, X, *args, **kwargs):
        time.sleep(PREDICT_DELAY_SECONDS)
        result = original_predict(self, X, *args, **kwargs)
        try:
            rows = len(X)
        except Exception:
            rows = None
        telemetry['predictions'].append({
            'rows': rows,
            'n_estimators': getattr(self, 'n_estimators', None),
            'max_depth': getattr(self, 'max_depth', None),
        })
        return result

    def instrumented_grid_fit(self, X, y=None, **params):
        cv = getattr(self, 'cv', None)
        if isinstance(cv, int):
            cv_splits = cv
        else:
            try:
                cv_splits = cv.get_n_splits(X, y)
            except Exception:
                cv_splits = None
        estimator = getattr(self, 'estimator', None)
        event = {
            'train_rows': len(X),
            'cv_splits': cv_splits,
            'scoring': getattr(self, 'scoring', None),
            'estimator_type': type(estimator).__name__,
            'random_state': getattr(estimator, 'random_state', None),
            'param_grid': getattr(self, 'param_grid', None),
        }
        result = original_grid_fit(self, X, y, **params)
        event['best_params'] = getattr(self, 'best_params_', None)
        event['best_score'] = getattr(self, 'best_score_', None)
        telemetry['grid_searches'].append(event)
        return result

    RandomForestClassifier.predict = instrumented_predict
    GridSearchCV.fit = instrumented_grid_fit
except Exception as exc:
    telemetry['instrumentation_error'] = repr(exc)

@atexit.register
def write_telemetry():
    try:
        with open(TELEMETRY_PATH, 'w') as f:
            json.dump(telemetry, f, default=str)
    except Exception:
        pass
PY

if [ -z "$SCRIPT_PATH" ] || [ ! -f "$SCRIPT_PATH" ]; then
    echo "No submitted Python script found" > "$EXECUTION_FAILURE"
else
    if ! (cd /home/user && PYTHONPATH="/tmp/verifier_instrument${PYTHONPATH:+:$PYTHONPATH}" timeout 900s python3 "$SCRIPT_PATH"); then
        echo "Submitted Python script failed during verifier execution" > "$EXECUTION_FAILURE"
    fi
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import statistics
import time

import pytest
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import GridSearchCV, train_test_split

REPORT_PATH = '/home/user/report.json'
TELEMETRY_PATH = '/tmp/model_task_telemetry.json'
EXECUTION_FAILURE = '/tmp/model_task_execution_failed'
EXPECTED_KEYS = {'best_n_estimators', 'best_max_depth', 'cv_accuracy', 'avg_inference_time_ms'}

_reference = None

def reference_result():
    global _reference
    if _reference is not None:
        return _reference

    df = pd.read_csv('/home/user/data.csv')
    X = df.drop(columns=['target'])
    y = df['target']
    X_train, X_test, y_train, _ = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    search = GridSearchCV(
        RandomForestClassifier(random_state=42),
        {'n_estimators': [10, 50, 100], 'max_depth': [None, 5, 10]},
        cv=5,
    )
    search.fit(X_train, y_train)

    timings = []
    for _ in range(3):
        start = time.perf_counter()
        for __ in range(100):
            search.best_estimator_.predict(X_test)
        timings.append((time.perf_counter() - start) * 1000 / 100)

    _reference = {
        'best_n_estimators': search.best_params_['n_estimators'],
        'best_max_depth': search.best_params_['max_depth'],
        'cv_accuracy': round(float(search.best_score_), 4),
        'base_latency_ms': statistics.median(timings),
        'train_rows': len(X_train),
        'test_rows': len(X_test),
    }
    return _reference


def load_report():
    with open(REPORT_PATH, 'r') as f:
        return json.load(f)


def test_report_exists_and_valid_json():
    """Verify that /home/user/report.json exists and is valid JSON."""
    assert not os.path.exists(EXECUTION_FAILURE), open(EXECUTION_FAILURE).read() if os.path.exists(EXECUTION_FAILURE) else ''
    assert os.path.isfile(REPORT_PATH), f'Report file missing: {REPORT_PATH}'

    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {REPORT_PATH} is not valid JSON.')

    assert isinstance(data, dict), 'JSON root must be a dictionary.'


def test_report_contents():
    """Preserve the original deterministic report assertions."""
    assert os.path.isfile(REPORT_PATH), f'Report file missing: {REPORT_PATH}'
    data = load_report()

    expected_keys = {'best_n_estimators', 'best_max_depth', 'cv_accuracy', 'avg_inference_time_ms'}
    assert expected_keys.issubset(set(data.keys())), f'Missing keys in report.json. Expected: {expected_keys}'

    assert data['best_n_estimators'] == 100, f"Expected best_n_estimators to be 100, got {data['best_n_estimators']}"
    assert data['best_max_depth'] is None, f"Expected best_max_depth to be null (None), got {data['best_max_depth']}"
    assert data['cv_accuracy'] == 0.9381, f"Expected cv_accuracy to be 0.9381, got {data['cv_accuracy']}"

    avg_time = data['avg_inference_time_ms']
    assert isinstance(avg_time, float), f'Expected avg_inference_time_ms to be a float, got {type(avg_time)}'
    assert avg_time > 0, f'Expected avg_inference_time_ms to be > 0, got {avg_time}'


def test_report_matches_recomputed_grid_search():
    data = load_report()
    expected = reference_result()
    assert set(data) == EXPECTED_KEYS, f'Report must contain exactly these keys: {EXPECTED_KEYS}'
    assert data['best_n_estimators'] == expected['best_n_estimators']
    assert data['best_max_depth'] == expected['best_max_depth']
    assert data['cv_accuracy'] == expected['cv_accuracy']
    assert data['cv_accuracy'] == round(data['cv_accuracy'], 4)


def test_submitted_script_executed_required_work_and_measured_latency():
    assert os.path.isfile(TELEMETRY_PATH), 'No execution telemetry was produced by the submitted script'
    with open(TELEMETRY_PATH) as f:
        telemetry = json.load(f)
    assert 'instrumentation_error' not in telemetry, telemetry.get('instrumentation_error')

    expected = reference_result()
    matching_searches = []
    for event in telemetry.get('grid_searches', []):
        grid = event.get('param_grid')
        if not isinstance(grid, dict):
            continue
        if (event.get('train_rows') == expected['train_rows'] and
                event.get('cv_splits') == 5 and
                event.get('scoring') in (None, 'accuracy') and
                event.get('estimator_type') == 'RandomForestClassifier' and
                event.get('random_state') == 42 and
                grid.get('n_estimators') == [10, 50, 100] and
                grid.get('max_depth') == [None, 5, 10]):
            matching_searches.append(event)
    assert matching_searches, 'The executed script did not perform the required 5-fold Random Forest grid search'

    best_predictions = [
        event for event in telemetry.get('predictions', [])
        if event.get('rows') == expected['test_rows']
        and event.get('n_estimators') == expected['best_n_estimators']
        and event.get('max_depth') == expected['best_max_depth']
    ]
    assert len(best_predictions) >= 100, 'The best model was not used to predict the entire test set 100 times'

    data = load_report()
    measured = data['avg_inference_time_ms']
    assert math.isfinite(measured)
    assert measured == round(measured, 2), 'Inference latency must be rounded to 2 decimal places'

    # The submitted script was rerun with a known 15 ms delay added to every
    # RandomForest prediction. A correctly calculated per-run average must track
    # the independently benchmarked latency plus that delay, rather than being
    # an arbitrary positive number or the total time for all 100 predictions.
    expected_latency = expected['base_latency_ms'] + telemetry['predict_delay_ms']
    tolerance = max(5.0, expected_latency * 0.35)
    assert abs(measured - expected_latency) <= tolerance, (
        f'Reported latency {measured} ms is inconsistent with the observed '
        f'per-prediction latency of approximately {expected_latency:.2f} ms'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
