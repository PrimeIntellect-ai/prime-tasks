#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_probe
cat << 'PROBE_EOF' > /tmp/verifier_probe/sitecustomize.py
import hashlib
import json
import os
import numpy as np

TRACE = os.environ.get("VERIFIER_TRACE")

def fingerprint(value):
    array = np.asarray(value)
    contiguous = np.ascontiguousarray(array)
    return {
        "shape": list(array.shape),
        "dtype": str(array.dtype),
        "sha256": hashlib.sha256(contiguous.tobytes()).hexdigest(),
    }

def emit(event, **fields):
    if not TRACE:
        return
    record = {"event": event, **fields}
    with open(TRACE, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, sort_keys=True) + "\n")

try:
    import inspect
    import sklearn.model_selection
    from sklearn.pipeline import Pipeline

    original_split = sklearn.model_selection.train_test_split
    split_signature = inspect.signature(original_split)

    def checked_split(*args, **kwargs):
        bound = split_signature.bind_partial(*args, **kwargs)
        bound.apply_defaults()
        result = original_split(*args, **kwargs)
        random_state = bound.arguments.get("random_state")
        if isinstance(random_state, (int, float, str, bool)) or random_state is None:
            logged_random_state = random_state
        else:
            logged_random_state = repr(random_state)
        emit(
            "train_test_split",
            test_size=bound.arguments.get("test_size"),
            random_state=logged_random_state,
            input_x=fingerprint(args[0]),
            input_y=fingerprint(args[1]),
            train_x=fingerprint(result[0]),
            test_x=fingerprint(result[1]),
            train_y=fingerprint(result[2]),
            test_y=fingerprint(result[3]),
        )
        return result

    sklearn.model_selection.train_test_split = checked_split

    original_fit = Pipeline.fit
    def checked_fit(self, X, y=None, **params):
        emit(
            "pipeline_fit",
            steps=[type(step).__name__ for _, step in self.steps],
            x=fingerprint(X),
            y=fingerprint(y),
        )
        return original_fit(self, X, y, **params)
    Pipeline.fit = checked_fit

    original_predict = Pipeline.predict
    def checked_predict(self, X, **params):
        emit(
            "pipeline_predict",
            steps=[type(step).__name__ for _, step in self.steps],
            x=fingerprint(X),
        )
        return original_predict(self, X, **params)
    Pipeline.predict = checked_predict
except Exception as exc:
    emit("probe_error", error=repr(exc))
PROBE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import subprocess

import numpy as np
import pandas as pd
import pytest
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split
from sklearn.naive_bayes import GaussianNB
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

VENV_PYTHON = '/home/user/venv/bin/python'
PIPELINE_PATH = '/home/user/experiment/pipeline.py'
METRICS_PATH = '/home/user/experiment/artifacts/final_metrics.json'
TRACE_PATH = '/tmp/pipeline_execution_trace.jsonl'

def fingerprint(value):
    array = np.asarray(value)
    contiguous = np.ascontiguousarray(array)
    return {
        'shape': list(array.shape),
        'dtype': str(array.dtype),
        'sha256': hashlib.sha256(contiguous.tobytes()).hexdigest(),
    }

@pytest.fixture(scope='session', autouse=True)
def execute_submitted_pipeline():
    if os.path.exists(METRICS_PATH):
        os.remove(METRICS_PATH)
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)

    env = os.environ.copy()
    old_pythonpath = env.get('PYTHONPATH', '')
    env['PYTHONPATH'] = '/tmp/verifier_probe' + (os.pathsep + old_pythonpath if old_pythonpath else '')
    env['VERIFIER_TRACE'] = TRACE_PATH

    result = subprocess.run(
        [VENV_PYTHON, PIPELINE_PATH],
        cwd='/home/user/experiment',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        'pipeline.py did not execute successfully with the virtual-environment Python.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )

def test_venv_exists():
    venv_path = '/home/user/venv'
    assert os.path.isdir(venv_path), f"Virtual environment directory {venv_path} does not exist."

    bin_path = os.path.join(venv_path, 'bin', 'python')
    if not os.path.exists(bin_path):
        bin_path = os.path.join(venv_path, 'Scripts', 'python.exe')
    assert os.path.isfile(bin_path), f"Python executable not found in virtual environment at {bin_path}."

    result = subprocess.run(
        [bin_path, '-c', 'import sklearn, pandas, numpy'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"Required packages are unavailable in the virtual environment: {result.stderr}"

def test_pipeline_script_content():
    pipeline_path = '/home/user/experiment/pipeline.py'
    assert os.path.isfile(pipeline_path), f"The script {pipeline_path} is missing."

    with open(pipeline_path, 'r') as f:
        content = f.read()

    assert "GaussianNB" in content, "The script does not use GaussianNB as required."
    assert "Pipeline" in content, "The script does not use sklearn.pipeline.Pipeline to fix the data leak."
    assert "RandomForestClassifier" not in content, "The script still contains RandomForestClassifier instead of GaussianNB."

def test_pipeline_was_executed_without_leakage():
    assert os.path.isfile(TRACE_PATH), 'No execution trace was produced by pipeline.py.'
    with open(TRACE_PATH, encoding='utf-8') as handle:
        events = [json.loads(line) for line in handle if line.strip()]

    assert not any(event.get('event') == 'probe_error' for event in events), 'The execution probe failed.'

    df = pd.read_csv('/home/user/experiment/data.csv')
    X = df.drop('target', axis=1)
    y = df['target']
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    matching_splits = [
        event for event in events
        if event.get('event') == 'train_test_split'
        and event.get('test_size') == 0.2
        and event.get('random_state') == 42
        and event.get('input_x') == fingerprint(X)
        and event.get('input_y') == fingerprint(y)
        and event.get('train_x') == fingerprint(X_train)
        and event.get('test_x') == fingerprint(X_test)
        and event.get('train_y') == fingerprint(y_train)
        and event.get('test_y') == fingerprint(y_test)
    ]
    assert matching_splits, 'The dataset was not split first with test_size=0.2 and random_state=42.'

    fits = [event for event in events if event.get('event') == 'pipeline_fit']
    assert any(
        event.get('steps') == ['StandardScaler', 'GaussianNB']
        and event.get('x') == fingerprint(X_train)
        and event.get('y') == fingerprint(y_train)
        for event in fits
    ), 'A Pipeline containing StandardScaler and GaussianNB was not fitted only on the training split.'

    predictions = [event for event in events if event.get('event') == 'pipeline_predict']
    assert any(
        event.get('steps') == ['StandardScaler', 'GaussianNB']
        and event.get('x') == fingerprint(X_test)
        for event in predictions
    ), 'The fitted StandardScaler/GaussianNB Pipeline was not used to predict the test split.'

def test_final_metrics_json():
    metrics_path = '/home/user/experiment/artifacts/final_metrics.json'
    assert os.path.isfile(metrics_path), f"The metrics file {metrics_path} is missing."

    with open(metrics_path, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {metrics_path} does not contain valid JSON.")

    assert "accuracy" in metrics, "The JSON file does not contain the 'accuracy' key."

    accuracy = metrics["accuracy"]
    assert isinstance(accuracy, (int, float)), "The accuracy value should be a number."

    expected_accuracy = 0.81
    assert math.isclose(accuracy, expected_accuracy, rel_tol=1e-2), \
        f"Expected accuracy to be approximately {expected_accuracy}, but got {accuracy}. Check if the data leak was properly fixed and the correct model was used."

    df = pd.read_csv('/home/user/experiment/data.csv')
    X = df.drop('target', axis=1)
    y = df['target']
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    reference_pipeline = Pipeline([
        ('scaler', StandardScaler()),
        ('model', GaussianNB()),
    ])
    reference_pipeline.fit(X_train, y_train)
    derived_accuracy = float(accuracy_score(y_test, reference_pipeline.predict(X_test)))
    assert math.isclose(float(accuracy), derived_accuracy, rel_tol=0.0, abs_tol=1e-12), (
        f"Recorded accuracy {accuracy} does not equal the independently recomputed accuracy {derived_accuracy}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
