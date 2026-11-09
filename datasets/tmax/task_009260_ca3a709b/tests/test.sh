#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'HARNESS_EOF' > /tmp/run_model_instrumented.py
import json
import os
import runpy

import numpy as np
import pymc as pm

evidence = {
    "exponential_called": False,
    "poisson_called": False,
    "poisson_observed": None,
    "sample_called": False,
    "sample_kwargs": None,
    "posterior_mean_lam": None,
}

_original_exponential = pm.Exponential
_original_poisson = pm.Poisson
_original_sample = pm.sample

def checked_exponential(*args, **kwargs):
    name = args[0] if args else kwargs.get("name")
    if name == "lam":
        evidence["exponential_called"] = True
    return _original_exponential(*args, **kwargs)

def checked_poisson(*args, **kwargs):
    observed = kwargs.get("observed")
    evidence["poisson_called"] = True
    if observed is not None:
        evidence["poisson_observed"] = np.asarray(observed).tolist()
    return _original_poisson(*args, **kwargs)

def checked_sample(*args, **kwargs):
    evidence["sample_called"] = True
    evidence["sample_kwargs"] = {
        key: kwargs.get(key)
        for key in ("draws", "tune", "random_seed", "return_inferencedata")
    }
    result = _original_sample(*args, **kwargs)
    evidence["posterior_mean_lam"] = float(result.posterior["lam"].mean().item())
    return result

pm.Exponential = checked_exponential
pm.Poisson = checked_poisson
pm.sample = checked_sample

runpy.run_path('/home/user/model.py', run_name='__main__')

with open(os.environ['VERIFIER_EVIDENCE'], 'w', encoding='utf-8') as f:
    json.dump(evidence, f)
HARNESS_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import shutil
import subprocess
import time


def test_execute_pipeline_and_model():
    clean_path = '/home/user/clean_data.csv'
    run_id_path = '/home/user/run_id.txt'
    tracking_dir = '/home/user/mlruns'
    evidence_path = '/tmp/verifier_model_evidence.json'

    for path in (clean_path, run_id_path, evidence_path):
        if os.path.lexists(path):
            os.remove(path)
    if os.path.lexists(tracking_dir):
        if os.path.islink(tracking_dir) or not os.path.isdir(tracking_dir):
            os.remove(tracking_dir)
        else:
            shutil.rmtree(tracking_dir)

    started_ms = int(time.time() * 1000)

    preprocessing = subprocess.run(
        ['python3', '/home/user/preprocess.py'],
        cwd='/home/user', text=True, capture_output=True, timeout=120
    )
    assert preprocessing.returncode == 0, (
        'preprocess.py failed:\n' + preprocessing.stdout + preprocessing.stderr
    )

    env = os.environ.copy()
    env['MLFLOW_TRACKING_URI'] = 'file:///home/user/mlruns'
    env['VERIFIER_EVIDENCE'] = evidence_path
    modeling = subprocess.run(
        ['python3', '/tmp/run_model_instrumented.py'],
        cwd='/home/user', env=env, text=True, capture_output=True, timeout=600
    )
    assert modeling.returncode == 0, (
        'model.py failed:\n' + modeling.stdout[-4000:] + modeling.stderr[-4000:]
    )
    assert os.path.exists(evidence_path), 'No PyMC execution evidence was produced.'

    with open(evidence_path, encoding='utf-8') as f:
        evidence = json.load(f)
    assert evidence['exponential_called'], "model.py did not create the 'lam' Exponential prior."
    assert evidence['poisson_called'], 'model.py did not create a PyMC Poisson likelihood.'
    assert evidence['poisson_observed'] == [3, 1, 0, 0, 2], (
        f"Poisson received unexpected observations: {evidence['poisson_observed']}"
    )
    assert evidence['sample_called'], 'model.py did not call pymc.sample.'
    assert evidence['posterior_mean_lam'] is not None

    assert os.path.exists(run_id_path), f'File {run_id_path} does not exist.'
    with open(run_id_path, encoding='utf-8') as f:
        run_id = f.read().strip()
    assert run_id, 'run_id.txt is empty.'

    from mlflow.tracking import MlflowClient
    client = MlflowClient(tracking_uri='file:///home/user/mlruns')
    experiment = client.get_experiment_by_name('Defect_Analysis')
    assert experiment is not None, "MLflow experiment 'Defect_Analysis' was not created."

    run = client.get_run(run_id)
    assert run.info.experiment_id == experiment.experiment_id
    assert run.info.status == 'FINISHED', f"MLflow run status is {run.info.status}."
    assert run.info.start_time >= started_ms - 2000, 'The reported MLflow run is stale.'
    assert 'posterior_mean_lam' in run.data.metrics

    metric_value = float(run.data.metrics['posterior_mean_lam'])
    assert math.isfinite(metric_value)
    assert math.isclose(
        metric_value, float(evidence['posterior_mean_lam']), rel_tol=1e-10, abs_tol=1e-10
    ), 'The MLflow metric is not the posterior mean returned by pymc.sample.'

    history = client.get_metric_history(run_id, 'posterior_mean_lam')
    assert history, "MLflow has no history for metric 'posterior_mean_lam'."
    assert any(item.timestamp >= started_ms - 2000 for item in history)


def test_clean_data_csv():
    csv_path = '/home/user/clean_data.csv'
    assert os.path.exists(csv_path), f"File {csv_path} does not exist."

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert 'defect_count' in header, "Column 'defect_count' not found in clean_data.csv"

        idx = header.index('defect_count')
        defect_counts = []
        for row in reader:
            if len(row) > idx:
                val = row[idx]
                assert '.' not in val, f"Value '{val}' in defect_count is not formatted as an integer."
                defect_counts.append(val)

    expected = ['3', '1', '0', '0', '2']
    assert defect_counts == expected, f"Expected defect_count values {expected}, got {defect_counts}"

    import pandas as pd
    df = pd.read_csv(csv_path)
    assert str(df['defect_count'].dtype) == 'int64', (
        f"Expected defect_count dtype int64, got {df['defect_count'].dtype}"
    )


def test_mlflow_output():
    run_id_path = '/home/user/run_id.txt'
    assert os.path.exists(run_id_path), f"File {run_id_path} does not exist."

    with open(run_id_path, 'r', encoding='utf-8') as f:
        run_id = f.read().strip()

    assert run_id, "run_id.txt is empty."

    metric_found = False
    metric_value = None

    for root, dirs, files in os.walk('/home/user'):
        if run_id in root and 'metrics' in root:
            if 'posterior_mean_lam' in files:
                metric_found = True
                with open(os.path.join(root, 'posterior_mean_lam'), 'r') as mf:
                    content = mf.read().strip()
                    parts = content.split()
                    if len(parts) >= 2:
                        metric_value = float(parts[1])
                break

    assert metric_found, f"MLflow metric 'posterior_mean_lam' not found for run {run_id}."
    if metric_value is not None:
        assert 1.0 < metric_value < 1.3, f"Posterior mean {metric_value} is out of expected bounds (1.0, 1.3)."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
