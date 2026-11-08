#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import tempfile
import urllib.error
import urllib.request

import joblib
import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error

FEATURES = ['num_tokens', 'num_unique', 'char_per_token']


def engineered_features(frame):
    rows = []
    for value in frame['customer_query']:
        text = '' if pd.isna(value) else str(value)
        cleaned = re.sub(r'[^a-z0-9 ]', '', text.lower())
        tokens = cleaned.split()
        rows.append([
            len(tokens),
            len(set(tokens)),
            (sum(len(token) for token in tokens) / len(tokens)) if tokens else 0.0,
        ])
    return pd.DataFrame(rows, columns=FEATURES)


def parse_last_float(result, script_name='predict.py'):
    output = result.stdout.strip().splitlines()
    assert output, f'{script_name} produced no output.'
    last_line = output[-1].strip()
    try:
        return float(last_line)
    except ValueError:
        pytest.fail(f'Could not parse the last line of output as a float. Output was: {last_line}')


def run_predict(csv_path):
    try:
        result = subprocess.run(
            ['python3', '/home/user/predict.py', csv_path],
            capture_output=True,
            text=True,
            check=True,
            timeout=60,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f'Executing predict.py failed with error:\n{e.stderr}')
    except subprocess.TimeoutExpired:
        pytest.fail('Executing predict.py timed out.')
    return parse_last_float(result)


def test_train_csv_exists():
    assert os.path.isfile('/home/user/train.csv'), '/home/user/train.csv is missing. The data was not downloaded correctly.'
    with open('/home/user/train.csv', 'rb') as submitted, open('/app/raw.csv', 'rb') as source:
        assert submitted.read() == source.read(), '/home/user/train.csv is not the dataset served from /app/raw.csv.'


def test_data_service_works():
    try:
        with urllib.request.urlopen('http://localhost:8000/data.csv', timeout=10) as response:
            served = response.read()
    except urllib.error.URLError as e:
        pytest.fail(f'Could not connect to the data API: {e}')
    with open('/app/raw.csv', 'rb') as source:
        assert served == source.read(), 'The data API did not return the raw CSV dataset.'


def test_model_pkl_exists():
    assert os.path.isfile('/home/user/model.pkl'), '/home/user/model.pkl is missing. The model was not saved.'
    model = joblib.load('/home/user/model.pkl')
    assert isinstance(model, Ridge), 'model.pkl must contain a scikit-learn Ridge model.'
    assert getattr(model, 'n_features_in_', None) == 3, 'The Ridge model must use exactly the three engineered features.'
    assert model.get_params() == Ridge().get_params(), 'The Ridge model was not configured with default parameters.'


def test_predict_script_exists():
    assert os.path.isfile('/home/user/predict.py'), '/home/user/predict.py is missing.'
    assert os.path.isfile('/home/user/train_model.py'), '/home/user/train_model.py is missing.'


def test_predict_mse_threshold():
    test_frame = pd.read_csv('/app/test_secret.csv')
    model = joblib.load('/home/user/model.pkl')
    expected_predictions = model.predict(engineered_features(test_frame))
    actual_mse = mean_squared_error(test_frame['resolution_time'], expected_predictions)

    reported_mse = run_predict('/app/test_secret.csv')
    assert reported_mse == pytest.approx(round(actual_mse, 2), abs=0.005), (
        f'predict.py reported {reported_mse}, but the saved model and required feature engineering produce {actual_mse:.2f}.'
    )
    assert actual_mse <= 45.0, f'MSE {actual_mse} is not <= 45.0. Model performance is inadequate.'
    assert reported_mse <= 45.0, f'MSE {reported_mse} is not <= 45.0. Model performance is inadequate.'


def test_predict_engineering_on_independent_input():
    nonce = secrets.token_hex(8)
    probe = pd.DataFrame({
        'customer_query': [
            f'HELLO,{nonce} hello!!!',
            'One-Two THREE  three',
            'A1 b22 C333 c333',
            f'punctuation...joins {nonce.upper()}?',
        ],
        'resolution_time': [
            7.0 + secrets.randbelow(100) / 10.0,
            19.0 + secrets.randbelow(100) / 10.0,
            31.0 + secrets.randbelow(100) / 10.0,
            43.0 + secrets.randbelow(100) / 10.0,
        ],
    })
    model = joblib.load('/home/user/model.pkl')
    expected = mean_squared_error(
        probe['resolution_time'], model.predict(engineered_features(probe))
    )
    with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as handle:
        probe.to_csv(handle.name, index=False)
        probe_path = handle.name
    try:
        reported = run_predict(probe_path)
    finally:
        os.unlink(probe_path)
    assert reported == pytest.approx(round(expected, 2), abs=0.005), (
        'predict.py does not apply the required tokenizer/features and saved model to arbitrary input.'
    )


def test_mlflow_tracking():
    try:
        url = 'http://localhost:5000/api/2.0/mlflow/experiments/get-by-name?experiment_name=Support_Analysis'
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            exp_data = json.loads(response.read().decode())

        assert 'experiment' in exp_data, "Experiment 'Support_Analysis' not found in MLflow."
        exp_id = exp_data['experiment']['experiment_id']

        search_url = 'http://localhost:5000/api/2.0/mlflow/runs/search'
        search_payload = json.dumps({'experiment_ids': [exp_id]}).encode('utf-8')
        req2 = urllib.request.Request(search_url, data=search_payload, headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req2) as response:
            runs_data = json.loads(response.read().decode())

        runs = runs_data.get('runs', [])
        assert len(runs) > 0, "No runs found in the 'Support_Analysis' experiment."

        metrics = runs[0].get('data', {}).get('metrics', [])
        metric_keys = [m['key'] for m in metrics]
        assert len(metrics) >= 3, f'Expected at least 3 metrics logged, found {len(metrics)}. Keys: {metric_keys}'

        train = pd.read_csv('/home/user/train.csv')
        values = engineered_features(train)
        values['resolution_time'] = train['resolution_time'].to_numpy()
        expected_corr = values.corr(method='pearson')['resolution_time']

        valid_run_found = False
        for run in runs:
            run_metrics = run.get('data', {}).get('metrics', [])
            matched = {}
            for metric in run_metrics:
                normalized_key = re.sub(r'[^a-z0-9]', '', metric.get('key', '').lower())
                for feature in FEATURES:
                    normalized_feature = re.sub(r'[^a-z0-9]', '', feature.lower())
                    if normalized_feature in normalized_key:
                        matched[feature] = float(metric['value'])
            if all(feature in matched for feature in FEATURES) and all(
                np.isclose(matched[feature], float(expected_corr[feature]), rtol=1e-5, atol=1e-6)
                for feature in FEATURES
            ):
                valid_run_found = True
                break

        assert valid_run_found, (
            'No MLflow run logged correctly named correlation metrics with the Pearson correlation values '
            'for num_tokens, num_unique, and char_per_token.'
        )

    except urllib.error.URLError as e:
        pytest.fail(f'Could not connect to MLflow server: {e}')
    except Exception as e:
        pytest.fail(f'MLflow validation failed: {e}')
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
