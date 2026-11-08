#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd


def test_json_results():
    json_path = '/home/user/test_results.json'
    assert os.path.exists(json_path), f"JSON results file {json_path} is missing."

    with open(json_path, 'r') as f:
        try:
            res = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} does not contain valid JSON."

    assert 'test_accuracy' in res, "The key 'test_accuracy' is missing in the JSON file."
    assert isinstance(res['test_accuracy'], float), "The value of 'test_accuracy' must be a float."


def test_mlflow_tracking():
    mlruns_dir = '/home/user/mlruns'
    assert os.path.isdir(mlruns_dir), f"MLflow tracking directory {mlruns_dir} is missing."

    exp_id = None
    for item in os.listdir(mlruns_dir):
        exp_dir = os.path.join(mlruns_dir, item)
        if os.path.isdir(exp_dir):
            meta_path = os.path.join(exp_dir, 'meta.yaml')
            if os.path.exists(meta_path):
                with open(meta_path, 'r') as f:
                    content = f.read()
                    if 'name: Sensor_Failure_Exp' in content:
                        exp_id = item
                        break

    assert exp_id is not None, "Experiment 'Sensor_Failure_Exp' not found in mlruns."

    exp_dir = os.path.join(mlruns_dir, exp_id)
    run_dirs = [d for d in os.listdir(exp_dir)
                if os.path.isdir(os.path.join(exp_dir, d)) and d != '.trash']
    assert len(run_dirs) > 0, "No MLflow runs found for the experiment."

    success = False
    for run_id in run_dirs:
        run_dir = os.path.join(exp_dir, run_id)
        param_path = os.path.join(run_dir, 'params', 'n_estimators')
        if not os.path.exists(param_path):
            continue
        with open(param_path, 'r') as f:
            if f.read().strip() != '50':
                continue

        metric_path = os.path.join(run_dir, 'metrics', 'test_accuracy')
        if not os.path.exists(metric_path):
            continue

        tag_path = os.path.join(run_dir, 'tags', 'pipeline_version')
        if not os.path.exists(tag_path):
            continue
        with open(tag_path, 'r') as f:
            if f.read().strip() != 'v1.0':
                continue

        artifact_dir = os.path.join(run_dir, 'artifacts', 'rf_model')
        if not os.path.isdir(artifact_dir):
            continue

        success = True
        break

    assert success, "Could not find an MLflow run with the correct parameters, metrics, tags, and artifacts."


def _reference_result():
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.metrics import accuracy_score
    from sklearn.model_selection import train_test_split
    from sklearn.preprocessing import StandardScaler

    df = pd.read_csv('/home/user/sensor_data.csv')
    required = [f'sensor_{i}' for i in range(1, 6)] + ['target']
    assert list(df.columns) == required, 'The supplied sensor data has unexpected columns.'

    df = df.copy()
    df['sensor_3'] = df['sensor_3'].fillna(df['sensor_3'].median())
    feature_cols = [f'sensor_{i}' for i in range(1, 6)]
    X = StandardScaler().fit_transform(df[feature_cols])
    y = df['target']
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    model = RandomForestClassifier(
        n_estimators=50, max_depth=5, random_state=42
    )
    model.fit(X_train, y_train)
    accuracy = float(accuracy_score(y_test, model.predict(X_test)))
    return model, X_test, accuracy


def _validate_generated_outputs():
    import mlflow
    import mlflow.sklearn
    from mlflow.tracking import MlflowClient
    from sklearn.ensemble import RandomForestClassifier

    expected_model, X_test, expected_accuracy = _reference_result()

    json_path = '/home/user/test_results.json'
    assert os.path.isfile(json_path), 'Executing the pipeline did not create test_results.json.'
    with open(json_path) as f:
        result = json.load(f)
    assert 'test_accuracy' in result
    assert isinstance(result['test_accuracy'], float)
    assert abs(result['test_accuracy'] - expected_accuracy) <= 1e-12, (
        f"JSON accuracy {result['test_accuracy']} does not equal the recomputed "
        f"accuracy {expected_accuracy}."
    )

    tracking_uri = 'file:///home/user/mlruns'
    mlflow.set_tracking_uri(tracking_uri)
    client = MlflowClient(tracking_uri=tracking_uri)
    experiment = client.get_experiment_by_name('Sensor_Failure_Exp')
    assert experiment is not None, 'The required MLflow experiment was not created.'
    runs = client.search_runs([experiment.experiment_id])
    assert runs, 'The required experiment contains no MLflow runs.'

    valid = []
    errors = []
    for run in runs:
        if run.data.params.get('n_estimators') != '50':
            continue
        if run.data.tags.get('pipeline_version') != 'v1.0':
            continue
        metric = run.data.metrics.get('test_accuracy')
        if metric is None or abs(float(metric) - expected_accuracy) > 1e-12:
            continue
        if abs(float(metric) - result['test_accuracy']) > 1e-12:
            continue

        artifact_dir = os.path.join(
            '/home/user/mlruns', experiment.experiment_id, run.info.run_id,
            'artifacts', 'rf_model'
        )
        if not os.path.isdir(artifact_dir) or not os.listdir(artifact_dir):
            continue
        if not os.path.isfile(os.path.join(artifact_dir, 'MLmodel')):
            continue

        try:
            model = mlflow.sklearn.load_model(artifact_dir)
            assert isinstance(model, RandomForestClassifier)
            assert model.n_estimators == 50
            assert model.max_depth == 5
            assert model.random_state == 42
            assert hasattr(model, 'estimators_') and len(model.estimators_) == 50

            np.testing.assert_array_equal(model.classes_, expected_model.classes_)
            np.testing.assert_array_equal(model.predict(X_test), expected_model.predict(X_test))
            np.testing.assert_allclose(
                model.predict_proba(X_test), expected_model.predict_proba(X_test),
                rtol=0, atol=1e-15
            )

            # Comparing every fitted tree verifies the prescribed imputation,
            # scaling, split, training data, and deterministic RF configuration.
            for actual_tree, reference_tree in zip(model.estimators_, expected_model.estimators_):
                a = actual_tree.tree_
                b = reference_tree.tree_
                np.testing.assert_array_equal(a.children_left, b.children_left)
                np.testing.assert_array_equal(a.children_right, b.children_right)
                np.testing.assert_array_equal(a.feature, b.feature)
                np.testing.assert_allclose(a.threshold, b.threshold, rtol=0, atol=1e-14)
                np.testing.assert_allclose(a.value, b.value, rtol=0, atol=1e-14)
            valid.append(run.info.run_id)
        except Exception as exc:
            errors.append(f'{run.info.run_id}: {exc}')

    assert valid, (
        'No genuine MLflow run contains the recomputed metric and the exact fitted '
        'RandomForest model required by the pipeline. ' + '; '.join(errors)
    )


def test_pipeline_can_be_executed_and_reproduces_outputs():
    # The task requires a Python pipeline, not merely a hand-created output tree.
    candidates = []
    for path in Path('/home/user').rglob('*.py'):
        if 'mlruns' in path.parts or any(part.startswith('.') for part in path.parts):
            continue
        try:
            text = path.read_text(errors='ignore')
        except OSError:
            continue
        required_markers = [
            'sensor_data.csv', 'StandardScaler', 'train_test_split',
            'RandomForestClassifier', 'mlflow', 'test_results.json'
        ]
        if all(marker in text for marker in required_markers):
            candidates.append(path)

    assert candidates, 'No executable Python pipeline was found under /home/user.'

    # Remove prior results so a candidate must itself recreate all required output.
    for output in ['/home/user/mlruns', '/home/user/test_results.json']:
        if os.path.isdir(output):
            shutil.rmtree(output)
        elif os.path.exists(output):
            os.remove(output)

    failures = []
    for candidate in candidates:
        for output in ['/home/user/mlruns', '/home/user/test_results.json']:
            if os.path.isdir(output):
                shutil.rmtree(output)
            elif os.path.exists(output):
                os.remove(output)
        try:
            proc = subprocess.run(
                ['python3', str(candidate)], cwd=str(candidate.parent),
                env={**os.environ, 'HOME': '/home/user'},
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, timeout=300
            )
        except Exception as exc:
            failures.append(f'{candidate}: {exc}')
            continue
        if proc.returncode != 0:
            failures.append(f'{candidate}: exit {proc.returncode}: {proc.stdout[-1000:]}')
            continue
        try:
            _validate_generated_outputs()
            return
        except Exception as exc:
            failures.append(f'{candidate}: {exc}')

    assert False, 'No pipeline candidate reproduced valid outputs: ' + ' | '.join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
