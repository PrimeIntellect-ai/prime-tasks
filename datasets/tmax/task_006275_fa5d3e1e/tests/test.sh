#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import subprocess

RUN_SH = '/home/user/run.sh'
PIPELINE = '/home/user/pipeline.py'
RESULTS = '/home/user/results.json'
TELEMETRY = '/home/user/telemetry.csv'
VENV_PYTHON = '/home/user/venv/bin/python'


def compute_expected():
    script = r'''
import json
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression
from scipy.stats import ttest_ind

df = pd.read_csv('/home/user/telemetry.csv')
X = df.drop('label', axis=1)
y = df['label']

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled = scaler.transform(X_test)

pca = PCA(n_components=2)
X_train_pca = pca.fit_transform(X_train_scaled)
X_test_pca = pca.transform(X_test_scaled)

clf = LogisticRegression(random_state=42)
clf.fit(X_train_pca, y_train)
acc = float(clf.score(X_test_pca, y_test))

pc1_test = X_test_pca[:, 0]
_, p_value = ttest_ind(pc1_test[y_test == 0], pc1_test[y_test == 1])
print(json.dumps({'accuracy': acc, 'p_value': float(p_value)}))
'''
    result = subprocess.run(
        [VENV_PYTHON, '-c', script], capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, (
        f'Failed to compute expected metrics using {VENV_PYTHON}:\n{result.stderr}'
    )
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        assert False, f'Failed to parse expected metrics output:\n{result.stdout}'


def load_results():
    assert os.path.exists(RESULTS), f'{RESULTS} does not exist.'
    try:
        with open(RESULTS) as f:
            return json.load(f)
    except json.JSONDecodeError:
        assert False, f'{RESULTS} does not contain valid JSON.'


def assert_metrics(actual, expected):
    assert math.isclose(actual['accuracy'], expected['accuracy'], rel_tol=1e-3), (
        f"Expected accuracy ~{expected['accuracy']:.4f}, but got {actual['accuracy']}. "
        'Check data leakage fix.'
    )
    assert math.isclose(actual['p_value'], expected['p_value'], rel_tol=1e-3), (
        f"Expected p_value ~{expected['p_value']:.4e}, but got {actual['p_value']}. "
        'Check the hypothesis testing logic.'
    )


def test_run_sh_exists_executable_and_runs_pipeline():
    assert os.path.exists(RUN_SH), f'{RUN_SH} does not exist.'
    assert os.path.isfile(RUN_SH), f'{RUN_SH} is not a file.'
    assert os.access(RUN_SH, os.X_OK), f'{RUN_SH} is not executable.'
    assert os.path.exists(PIPELINE), f'{PIPELINE} does not exist.'
    assert os.path.isfile(PIPELINE), f'{PIPELINE} is not a file.'

    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    result = subprocess.run(
        [RUN_SH], capture_output=True, text=True, timeout=600, cwd='/home/user'
    )
    assert result.returncode == 0, (
        f'{RUN_SH} failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.exists(RESULTS), (
        f'{RUN_SH} did not execute the pipeline and create {RESULTS}.'
    )


def test_results_json_exists_and_keys():
    data = load_results()
    assert set(data.keys()) == {'accuracy', 'p_value'}, (
        "results.json must contain exactly 'accuracy' and 'p_value'."
    )
    assert isinstance(data['accuracy'], (float, int)) and not isinstance(data['accuracy'], bool), (
        'accuracy must be a number.'
    )
    assert isinstance(data['p_value'], (float, int)) and not isinstance(data['p_value'], bool), (
        'p_value must be a number.'
    )


def test_correct_metrics():
    assert os.path.exists(VENV_PYTHON), (
        f'Virtual environment python not found at {VENV_PYTHON}. Did run.sh create it?'
    )
    assert_metrics(load_results(), compute_expected())


def test_pipeline_recomputes_without_leakage_on_fresh_input():
    # Exercise pipeline.py itself on verifier-generated data so a prewritten
    # results.json or hard-coded metrics cannot satisfy the task.
    with open(TELEMETRY, 'rb') as f:
        original_telemetry = f.read()
    original_results = None
    if os.path.exists(RESULTS):
        with open(RESULTS, 'rb') as f:
            original_results = f.read()

    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    rows = []
    scores = []
    for _ in range(500):
        f1 = rng.gauss(0.0, 1.5)
        f2 = rng.gauss(4.0, 3.0)
        f3 = 1.7 * f1 + rng.gauss(0.0, 0.8)
        f4 = rng.uniform(-2.0, 2.0)
        f5 = rng.gauss(-1.0, 6.0)
        rows.append([f1, f2, f3, f4, f5])
        scores.append(f1 + 0.45 * f2 - 0.15 * f4 + rng.gauss(0.0, 0.35))
    cutoff = sorted(scores)[len(scores) // 2]

    try:
        with open(TELEMETRY, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['f1', 'f2', 'f3', 'f4', 'f5', 'label'])
            for features, score in zip(rows, scores):
                writer.writerow(features + [int(score > cutoff)])

        expected = compute_expected()
        if os.path.exists(RESULTS):
            os.remove(RESULTS)
        result = subprocess.run(
            [VENV_PYTHON, PIPELINE], capture_output=True, text=True, timeout=120,
            cwd='/home/user'
        )
        assert result.returncode == 0, (
            f'{PIPELINE} failed on valid telemetry input.\n'
            f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
        )
        actual = load_results()
        assert set(actual.keys()) == {'accuracy', 'p_value'}, (
            "results.json must contain exactly 'accuracy' and 'p_value'."
        )
        assert_metrics(actual, expected)
    finally:
        with open(TELEMETRY, 'wb') as f:
            f.write(original_telemetry)
        if original_results is None:
            if os.path.exists(RESULTS):
                os.remove(RESULTS)
        else:
            with open(RESULTS, 'wb') as f:
                f.write(original_results)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
