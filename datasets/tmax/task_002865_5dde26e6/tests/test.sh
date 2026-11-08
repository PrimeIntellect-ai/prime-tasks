#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/verifier_hook

cat << 'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import atexit
import hashlib
import json
import os
import time
import numpy as np

_EVENTS = {"splits": [], "scaler_fits": [], "model_fits": [], "predicts": []}
_AUDIT_PATH = os.environ.get("VERIFIER_AUDIT_PATH", "/tmp/train_model_audit.json")
_DELAY = float(os.environ.get("VERIFIER_PREDICT_DELAY", "0.1"))

def _fingerprint(value):
    arr = np.ascontiguousarray(np.asarray(value))
    h = hashlib.sha256()
    h.update(str(arr.shape).encode())
    h.update(str(arr.dtype).encode())
    h.update(arr.tobytes())
    return h.hexdigest()

def _write_audit():
    try:
        with open(_AUDIT_PATH, "w") as f:
            json.dump(_EVENTS, f)
    except Exception:
        pass

atexit.register(_write_audit)

try:
    import sklearn.model_selection as _ms
    _original_split = _ms.train_test_split

    def _audited_split(*arrays, **kwargs):
        result = _original_split(*arrays, **kwargs)
        event = {
            "test_size": kwargs.get("test_size"),
            "random_state": kwargs.get("random_state"),
        }
        if len(result) >= 2:
            event["train_hash"] = _fingerprint(result[0])
            event["test_hash"] = _fingerprint(result[1])
        _EVENTS["splits"].append(event)
        return result

    _ms.train_test_split = _audited_split

    from sklearn.preprocessing import StandardScaler as _StandardScaler
    _original_scaler_fit = _StandardScaler.fit

    def _audited_scaler_fit(self, X, y=None, sample_weight=None):
        _EVENTS["scaler_fits"].append({"input_hash": _fingerprint(X)})
        if sample_weight is None:
            return _original_scaler_fit(self, X, y)
        return _original_scaler_fit(self, X, y, sample_weight=sample_weight)

    _StandardScaler.fit = _audited_scaler_fit

    from sklearn.linear_model import LogisticRegression as _LogisticRegression
    _original_model_fit = _LogisticRegression.fit
    _original_predict = _LogisticRegression.predict

    def _audited_model_fit(self, X, y, sample_weight=None):
        _EVENTS["model_fits"].append({"random_state": self.random_state})
        if sample_weight is None:
            return _original_model_fit(self, X, y)
        return _original_model_fit(self, X, y, sample_weight=sample_weight)

    def _audited_predict(self, X):
        start = time.perf_counter()
        time.sleep(_DELAY)
        result = _original_predict(self, X)
        _EVENTS["predicts"].append({
            "input_hash": _fingerprint(X),
            "elapsed": time.perf_counter() - start,
        })
        return result

    _LogisticRegression.fit = _audited_model_fit
    _LogisticRegression.predict = _audited_predict
except Exception as exc:
    _EVENTS["hook_error"] = repr(exc)
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import secrets
import subprocess
import time

import pandas as pd
import pytest
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

SCRIPT = '/home/user/train_model.py'
METRICS = '/home/user/metrics.json'
PREDICTIONS = '/home/user/predictions.csv'
AUDIT = '/tmp/train_model_audit.json'


def _keyword_value(call, name):
    for keyword in call.keywords:
        if keyword.arg == name and isinstance(keyword.value, ast.Constant):
            return keyword.value.value
    return None


@pytest.fixture(scope='session', autouse=True)
def execute_and_validate_script():
    assert os.path.isfile(SCRIPT), f"Missing file: {SCRIPT}"
    with open(SCRIPT, 'r') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT)
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT} is not valid Python: {exc}")

    split_calls = []
    logistic_calls = []
    predict_lines = []
    clock_lines = []
    clock_names = {'time', 'time_ns', 'perf_counter', 'perf_counter_ns', 'monotonic', 'monotonic_ns'}

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = None
        if isinstance(node.func, ast.Name):
            name = node.func.id
        elif isinstance(node.func, ast.Attribute):
            name = node.func.attr

        if name == 'train_test_split':
            split_calls.append(node)
        elif name == 'LogisticRegression':
            logistic_calls.append(node)
        elif name == 'predict':
            predict_lines.append(node.lineno)
        elif name in clock_names:
            clock_lines.append(node.lineno)

    assert any(_keyword_value(c, 'test_size') == 0.2 and _keyword_value(c, 'random_state') == 42
               for c in split_calls), 'train_test_split must be called with test_size=0.2 and random_state=42'
    assert any(_keyword_value(c, 'random_state') == 42 for c in logistic_calls), \
        'LogisticRegression must be initialized with random_state=42'
    assert predict_lines, 'The script must call model.predict()'
    assert clock_lines and any(start <= pred <= end for pred in predict_lines
                               for start in clock_lines for end in clock_lines if start <= end), \
        'A clock measurement must surround the model.predict() call'

    for path in (METRICS, PREDICTIONS, AUDIT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    delay = 0.08 + secrets.randbelow(80) / 1000.0
    env = os.environ.copy()
    env['PYTHONPATH'] = '/tmp/verifier_hook' + (':' + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    env['VERIFIER_AUDIT_PATH'] = AUDIT
    env['VERIFIER_PREDICT_DELAY'] = str(delay)

    started = time.perf_counter()
    result = subprocess.run(
        ['python3', SCRIPT], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    runtime = time.perf_counter() - started
    assert result.returncode == 0, f"train_model.py failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert os.path.isfile(AUDIT), 'The executed script did not produce verifier audit data'

    with open(AUDIT, 'r') as f:
        audit = json.load(f)
    assert 'hook_error' not in audit, f"Instrumentation failed: {audit.get('hook_error')}"

    valid_splits = [s for s in audit.get('splits', [])
                    if s.get('test_size') == 0.2 and s.get('random_state') == 42]
    assert valid_splits, 'The executed pipeline did not split with test_size=0.2 and random_state=42'
    train_hashes = {s.get('train_hash') for s in valid_splits}
    scaler_hashes = {s.get('input_hash') for s in audit.get('scaler_fits', [])}
    assert train_hashes & scaler_hashes, \
        'StandardScaler was not fitted on the training features produced by train_test_split'
    assert any(m.get('random_state') == 42 for m in audit.get('model_fits', [])), \
        'The fitted LogisticRegression model did not have random_state=42'
    assert audit.get('predicts'), 'The executed pipeline did not call LogisticRegression.predict()'

    assert os.path.isfile(METRICS), f"Missing file after execution: {METRICS}"
    with open(METRICS, 'r') as f:
        metrics = json.load(f)
    measured = metrics.get('inference_time_seconds')
    assert isinstance(measured, (int, float)) and not isinstance(measured, bool)
    assert math.isfinite(measured)
    assert measured >= delay * 0.9, \
        'inference_time_seconds does not include the actual model.predict() call'
    assert measured <= runtime + 0.5, 'inference_time_seconds is not a plausible measured duration'


def test_metrics_json_exists_and_valid():
    path = '/home/user/metrics.json'
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} is not a valid JSON file.")

    assert "accuracy" in metrics, f"Missing 'accuracy' key in {path}"
    assert "inference_time_seconds" in metrics, f"Missing 'inference_time_seconds' key in {path}"
    assert round(metrics["accuracy"], 3) == 0.685, f"Expected accuracy to be approx 0.685, got {metrics['accuracy']}"
    assert isinstance(metrics["inference_time_seconds"], (int, float)), "inference_time_seconds must be a number"
    assert metrics["inference_time_seconds"] > 0, "inference_time_seconds must be greater than 0"


def test_predictions_csv_exists_and_valid():
    path = '/home/user/predictions.csv'
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"{path} is empty"
    header = rows[0]
    assert header == ["user_id", "predicted_churn"], f"Expected header ['user_id', 'predicted_churn'], got {header}"
    assert len(rows) == 201, f"Expected exactly 201 rows (including header), got {len(rows)}"

    for i, row in enumerate(rows[1:], start=2):
        assert len(row) == 2, f"Row {i} does not have exactly 2 columns"
        assert row[0].isdigit(), f"Row {i} user_id '{row[0]}' is not an integer"
        assert row[1] in ["0", "1", "0.0", "1.0", "False", "True"], f"Row {i} predicted_churn '{row[1]}' is not a valid binary prediction"


def test_outputs_match_recomputed_pipeline():
    users = pd.read_csv('/home/user/users.csv')
    tx = pd.read_csv('/home/user/transactions.csv')
    tx_agg = tx.groupby('user_id')['amount'].sum().reset_index()
    df = pd.merge(users, tx_agg, on='user_id', how='left').fillna(0)

    X = df[['age', 'amount']]
    y = df['churn']
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)
    model = LogisticRegression(random_state=42)
    model.fit(X_train_scaled, y_train)
    expected_predictions = model.predict(X_test_scaled)
    expected_accuracy = accuracy_score(y_test, expected_predictions)
    expected_ids = df.loc[X_test.index, 'user_id'].astype(int).tolist()

    with open(METRICS, 'r') as f:
        metrics = json.load(f)
    assert metrics['accuracy'] == pytest.approx(expected_accuracy, abs=1e-12)

    actual = pd.read_csv(PREDICTIONS)
    assert list(actual.columns) == ['user_id', 'predicted_churn']
    assert actual['user_id'].astype(int).tolist() == expected_ids, \
        'predictions.csv user_id values or order do not match the held-out test set'
    assert actual['predicted_churn'].astype(int).tolist() == expected_predictions.astype(int).tolist(), \
        'predictions.csv does not contain the model predictions for the held-out test set'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
