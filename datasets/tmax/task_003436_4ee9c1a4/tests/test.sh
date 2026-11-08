#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import urllib.parse
import urllib.request
from urllib.error import URLError

import numpy as np
import pandas as pd


def test_processed_csv_exists_and_correct():
    raw_path = '/home/user/raw_housing.csv'
    processed_path = '/home/user/processed_housing.csv'
    assert os.path.exists(processed_path), f"Processed CSV not found at {processed_path}"

    raw = pd.read_csv(raw_path)
    processed = pd.read_csv(processed_path)

    assert 'zip_code_encoded' in processed.columns, \
        "Column 'zip_code_encoded' missing in processed CSV"
    assert len(processed) == len(raw), \
        f"Expected {len(raw)} rows, found {len(processed)}"
    assert set(processed.columns) == set(raw.columns) | {'zip_code_encoded'}, \
        "Processed CSV must contain all original columns and only zip_code_encoded as the added column"

    pd.testing.assert_frame_equal(
        processed[list(raw.columns)].reset_index(drop=True),
        raw.reset_index(drop=True),
        check_dtype=False,
        check_names=True,
    )

    global_mean = raw['price'].mean()
    stats = raw.groupby('zip_code')['price'].agg(['count', 'mean'])
    smoothed = (stats['count'] * stats['mean'] + 15 * global_mean) / (stats['count'] + 15)
    expected = raw['zip_code'].map(smoothed).to_numpy(dtype=float)
    actual = pd.to_numeric(processed['zip_code_encoded'], errors='raise').to_numpy(dtype=float)
    assert np.allclose(actual, expected, rtol=0, atol=0.1), \
        f"Incorrect zip_code_encoded values. Expected {expected.tolist()}, got {actual.tolist()}"

    mask_99999 = processed['zip_code'].astype(str) == '99999'
    assert mask_99999.any(), "Row with zip_code '99999' not found in processed CSV"
    encoded_val = float(processed.loc[mask_99999, 'zip_code_encoded'].iloc[0])
    expected_val = 700312.5
    assert abs(encoded_val - expected_val) < 0.1, \
        f"Incorrect smoothed value for 99999. Expected ~{expected_val}, got {encoded_val}"


def api_json(url, data=None):
    headers = {'Content-Type': 'application/json'} if data is not None else {}
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"MLflow API responded with status {response.status}"
            return json.loads(response.read().decode('utf-8'))
    except URLError as e:
        raise AssertionError(
            f"Failed to connect to MLflow server at 127.0.0.1:5000. Is it running? Error: {e}"
        )


def artifact_files(run_id, path=''):
    query = urllib.parse.urlencode({'run_id': run_id, 'path': path})
    response = api_json(f"http://127.0.0.1:5000/api/2.0/mlflow/artifacts/list?{query}")
    results = []
    for entry in response.get('files', []):
        if entry.get('is_dir'):
            results.extend(artifact_files(run_id, entry['path']))
        else:
            results.append(entry)
    return results


def test_mlflow_tracking():
    url = "http://127.0.0.1:5000/api/2.0/mlflow/runs/search"
    data = json.dumps({"experiment_ids": ["0"]}).encode('utf-8')
    resp_data = api_json(url, data)

    runs = resp_data.get("runs", [])
    assert len(runs) > 0, "No MLflow runs found in experiment 0"

    named_runs = []
    for run in runs:
        info = run.get('info', {})
        run_data = run.get('data', {})
        tags = {t['key']: t['value'] for t in run_data.get('tags', [])}
        run_name = info.get('run_name') or tags.get('mlflow.runName')
        if run_name == 'Bayesian_Encoding':
            named_runs.append(run)

    assert named_runs, "No MLflow run named 'Bayesian_Encoding' found"

    failures = []
    for run in named_runs:
        run_data = run.get('data', {})
        params = {p['key']: p['value'] for p in run_data.get('params', [])}
        metrics = {m['key']: m['value'] for m in run_data.get('metrics', [])}
        run_id = run.get('info', {}).get('run_id')

        try:
            assert 'smoothing_weight' in params, \
                "Parameter 'smoothing_weight' not logged in MLflow"
            assert params['smoothing_weight'] in ['15', '15.0'], \
                f"Incorrect smoothing_weight logged. Expected 15, got {params['smoothing_weight']}"
            assert 'global_mean_price' in metrics, \
                "Metric 'global_mean_price' not logged in MLflow"
            assert abs(float(metrics['global_mean_price']) - 727000.0) < 0.1, \
                f"Incorrect global_mean_price logged. Expected ~727000.0, got {metrics['global_mean_price']}"
            assert run_id, "Named MLflow run is missing a run ID"

            files = artifact_files(run_id)
            matching = [f for f in files if os.path.basename(f.get('path', '')) == 'processed_housing.csv']
            assert matching, "processed_housing.csv was not logged as an artifact"
            return
        except AssertionError as exc:
            failures.append(str(exc))

    raise AssertionError(
        "No run named 'Bayesian_Encoding' contained all required tracking data and artifact: "
        + "; ".join(failures)
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
