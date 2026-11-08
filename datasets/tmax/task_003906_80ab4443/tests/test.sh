#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import subprocess
import tempfile
import uuid

import pytest

VENV_PYTHON = '/home/user/venv/bin/python'
PIPELINE = '/home/user/etl_pipeline.py'
METRICS = '/home/user/metrics.json'
TEXTS = '/home/user/texts.csv'
LABELS = '/home/user/labels.csv'


def test_venv_exists():
    venv_python = VENV_PYTHON
    assert os.path.isfile(venv_python), f"Virtual environment python executable not found at {venv_python}. Did you create the venv?"


def test_metrics_json_exists_and_valid():
    metrics_path = METRICS
    assert os.path.isfile(metrics_path), f"File not found: {metrics_path}. Did you run the pipeline successfully?"

    with open(metrics_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{metrics_path} does not contain valid JSON.")

    assert 'accuracy' in data, f"'accuracy' key missing in {metrics_path}"
    acc = data['accuracy']
    assert isinstance(acc, float), f"'accuracy' should be a float, got {type(acc)}"
    assert 0.0 <= acc <= 1.0, f"'accuracy' value out of expected bounds [0.0, 1.0]: {acc}"


def test_etl_pipeline_modified():
    pipeline_path = PIPELINE
    assert os.path.isfile(pipeline_path), f"File not found: {pipeline_path}"

    with open(pipeline_path, 'r') as f:
        content = f.read()

    has_drop = 'dropna' in content or 'notnull' in content or 'how=\'inner\'' in content or 'how="inner"' in content or 'inner' in content
    assert has_drop, "The ETL script does not seem to contain logic to drop missing values (e.g., dropna or inner join)."

    has_cast = 'astype(int)' in content or 'astype("int")' in content or "astype('int')" in content or "astype('int64')" in content or 'astype("int64")' in content or 'to_numeric' in content
    assert has_cast or has_drop, "The ETL script does not seem to contain logic to handle the missing values and fix the data type."
    assert has_cast, "The ETL script must explicitly cast the label column back to an integer dtype."


def test_venv_is_functional_and_has_dependencies():
    assert os.access(VENV_PYTHON, os.X_OK), f"{VENV_PYTHON} is not executable"
    code = (
        "import os,sys,pandas,sklearn; "
        "assert os.path.realpath(sys.prefix) == os.path.realpath('/home/user/venv'); "
        "print('ok')"
    )
    result = subprocess.run([VENV_PYTHON, '-c', code], text=True, capture_output=True, timeout=30)
    assert result.returncode == 0, f"The virtual environment is invalid or lacks pandas/scikit-learn:\n{result.stdout}\n{result.stderr}"


def _write_csv(path, fieldnames, rows):
    with open(path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _reference_accuracy():
    code = r'''import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
texts = pd.read_csv('/home/user/texts.csv')
labels = pd.read_csv('/home/user/labels.csv')
df = texts.merge(labels, on='id', how='left')
df = df.dropna(subset=['label']).copy()
df['label'] = df['label'].astype(int)
X = TfidfVectorizer().fit_transform(df['text'])
y = df['label']
model = LogisticRegression(random_state=42)
model.fit(X, y)
print(repr(float(accuracy_score(y, model.predict(X)))))
'''
    env = os.environ.copy()
    env.pop('PYTHONPATH', None)
    result = subprocess.run([VENV_PYTHON, '-c', code], text=True, capture_output=True, env=env, timeout=60)
    assert result.returncode == 0, f"Could not derive expected accuracy:\n{result.stdout}\n{result.stderr}"
    return float(result.stdout.strip().splitlines()[-1])


def _run_and_check(site_dir, marker):
    expected = _reference_accuracy()
    for path in (METRICS, marker):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env['PYTHONPATH'] = site_dir
    env['ETL_FIT_MARKER'] = marker
    result = subprocess.run([VENV_PYTHON, PIPELINE], cwd='/home/user', env=env,
                            text=True, capture_output=True, timeout=60)
    assert result.returncode == 0, f"The ETL pipeline failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(marker), "The pipeline did not train LogisticRegression with an integer, non-missing target aligned to X."
    assert os.path.isfile(METRICS), "Running the pipeline did not create metrics.json"
    with open(METRICS) as f:
        data = json.load(f)
    assert set(data) == {'accuracy'}, "metrics.json must contain the accuracy metric"
    actual = data['accuracy']
    assert isinstance(actual, float), f"'accuracy' should be a float, got {type(actual)}"
    assert actual == pytest.approx(expected, abs=1e-12), f"Incorrect training accuracy: expected {expected}, got {actual}"
    return actual


def test_pipeline_executes_and_computes_accuracy():
    original_texts = open(TEXTS, 'rb').read()
    original_labels = open(LABELS, 'rb').read()

    with tempfile.TemporaryDirectory(prefix='etl_verify_') as site_dir:
        marker = os.path.join(site_dir, 'fit.marker')
        sitecustomize = r'''import os
import numpy as np
from sklearn.linear_model import LogisticRegression
_original_fit = LogisticRegression.fit
def _checked_fit(self, X, y, *args, **kwargs):
    values = np.asarray(y)
    if values.ndim != 1 or values.dtype.kind not in ('i', 'u'):
        raise RuntimeError('target passed to fit is not an integer vector')
    if len(values) != X.shape[0]:
        raise RuntimeError('features and target are not aligned')
    if np.any(values != values):
        raise RuntimeError('target contains missing values')
    result = _original_fit(self, X, y, *args, **kwargs)
    with open(os.environ['ETL_FIT_MARKER'], 'w') as f:
        f.write(str(len(values)))
    return result
LogisticRegression.fit = _checked_fit
'''
        with open(os.path.join(site_dir, 'sitecustomize.py'), 'w') as f:
            f.write(sitecustomize)

        try:
            original_accuracy = _run_and_check(site_dir, marker)

            nonce = uuid.uuid4().hex
            rows = []
            labels = []
            row_id = 1
            for cls, token in enumerate(('amber', 'cobalt', 'violet')):
                for j in range(4):
                    rows.append({'id': row_id, 'text': f'{token} {token} feature{j} {nonce}'})
                    labels.append({'id': row_id, 'label': cls})
                    row_id += 1
            rows.extend([
                {'id': row_id, 'text': f'unlabelled noise one {nonce}'},
                {'id': row_id + 1, 'text': f'unlabelled noise two {nonce}'},
            ])
            _write_csv(TEXTS, ['id', 'text'], rows)
            _write_csv(LABELS, ['id', 'label'], labels)
            first_accuracy = _run_and_check(site_dir, marker)

            rows = [{'id': i, 'text': f'identical document {nonce}'} for i in range(1, 15)]
            values = [0] * 7 + [1] * 3 + [2] * 2
            labels = [{'id': i + 1, 'label': value} for i, value in enumerate(values)]
            _write_csv(TEXTS, ['id', 'text'], rows)
            _write_csv(LABELS, ['id', 'label'], labels)
            second_accuracy = _run_and_check(site_dir, marker)
            assert first_accuracy != second_accuracy, "Challenge cases must produce distinct metrics"
        finally:
            with open(TEXTS, 'wb') as f:
                f.write(original_texts)
            with open(LABELS, 'wb') as f:
                f.write(original_labels)

        restored_accuracy = _run_and_check(site_dir, marker)
        assert restored_accuracy == pytest.approx(original_accuracy, abs=1e-12)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
