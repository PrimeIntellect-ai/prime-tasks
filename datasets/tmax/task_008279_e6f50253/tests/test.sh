#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import math
import os

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import GridSearchCV

REPORT_PATH = '/home/user/mlops/report.json'


def compute_expected_report():
    """Recreate the provided datasets and independently compute the required result."""
    np.random.seed(42)

    n_runs = 100
    run_ids = [f"run_{i}" for i in range(n_runs)]
    lrs = np.random.uniform(0.0001, 0.1, n_runs)
    batch_sizes = np.random.choice([16, 32, 64, 128], n_runs)
    latencies = np.random.uniform(10, 200, n_runs)
    accuracies = (
        0.95
        - (latencies / 1000)
        - (lrs * 0.5)
        + np.random.normal(0, 0.01, n_runs)
    )

    latencies[5] = 1500
    latencies[12] = -50
    latencies[45] = 1200
    accuracies[10] = np.nan
    accuracies[25] = np.nan
    accuracies[88] = np.nan

    runs = pd.DataFrame({
        'run_id': run_ids,
        'learning_rate': lrs,
        'batch_size': batch_sizes,
        'latency_ms': latencies,
        'accuracy': accuracies,
    })

    n_cands = 20
    cand_ids = [f"cand_{i}" for i in range(n_cands)]
    cand_lrs = np.random.uniform(0.0001, 0.1, n_cands)
    cand_batch_sizes = np.random.choice([16, 32, 64, 128], n_cands)
    cand_latencies = np.random.uniform(20, 100, n_cands)
    cand_latencies[2] = 30
    cand_latencies[7] = 45
    cand_latencies[15] = 25

    candidates = pd.DataFrame({
        'run_id': cand_ids,
        'learning_rate': cand_lrs,
        'batch_size': cand_batch_sizes,
        'latency_ms': cand_latencies,
    })

    # Match the CSV serialization and parsing used for the files supplied to the agent.
    runs_csv = io.StringIO()
    runs.to_csv(runs_csv, index=False)
    runs_csv.seek(0)
    runs = pd.read_csv(runs_csv)

    candidates_csv = io.StringIO()
    candidates.to_csv(candidates_csv, index=False)
    candidates_csv.seek(0)
    candidates = pd.read_csv(candidates_csv)

    cleaned = runs[(runs['latency_ms'] >= 0) & (runs['latency_ms'] <= 1000)].copy()
    cleaned['accuracy'] = cleaned['accuracy'].fillna(cleaned['accuracy'].mean())

    features = ['learning_rate', 'batch_size', 'latency_ms']
    search = GridSearchCV(
        RandomForestRegressor(random_state=42),
        {'max_depth': [2, 5, 10]},
        cv=3,
        scoring='neg_mean_squared_error',
    )
    search.fit(cleaned[features], cleaned['accuracy'])

    predictions = search.best_estimator_.predict(candidates[features])
    eligible = candidates[candidates['latency_ms'] <= 50].copy()
    eligible_predictions = predictions[candidates['latency_ms'].to_numpy() <= 50]
    best_position = int(np.argmax(eligible_predictions))

    return {
        'best_max_depth': int(search.best_params_['max_depth']),
        'recommended_run_id': str(eligible.iloc[best_position]['run_id']),
        'predicted_accuracy': float(eligible_predictions[best_position]),
    }


def test_report_exists():
    """Verify that the student generated the report.json file."""
    assert os.path.isfile(REPORT_PATH), \
        "The file /home/user/mlops/report.json is missing."


def test_report_contents():
    """Verify report.json against a result computed from the original inputs."""
    with open(REPORT_PATH, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, "report.json is not a valid JSON file."

    assert isinstance(report, dict), "report.json must contain a JSON object."

    assert "best_max_depth" in report, "Missing 'best_max_depth' in report.json."
    assert "recommended_run_id" in report, "Missing 'recommended_run_id' in report.json."
    assert "predicted_accuracy" in report, "Missing 'predicted_accuracy' in report.json."
    assert set(report) == {
        'best_max_depth', 'recommended_run_id', 'predicted_accuracy'
    }, "report.json contains unexpected keys."

    assert type(report['best_max_depth']) is int, \
        "'best_max_depth' must be an integer."
    assert type(report['recommended_run_id']) is str, \
        "'recommended_run_id' must be a string."
    assert type(report['predicted_accuracy']) is float, \
        "'predicted_accuracy' must be a float."

    expected = compute_expected_report()

    assert report['best_max_depth'] == expected['best_max_depth'], \
        f"Incorrect best_max_depth. Expected {expected['best_max_depth']}, got {report['best_max_depth']}."
    assert report['recommended_run_id'] == expected['recommended_run_id'], \
        f"Incorrect recommended_run_id. Expected '{expected['recommended_run_id']}', got '{report['recommended_run_id']}'."
    assert math.isclose(
        report['predicted_accuracy'],
        expected['predicted_accuracy'],
        rel_tol=1e-5,
    ), f"Incorrect predicted_accuracy. Expected {expected['predicted_accuracy']}, got {report['predicted_accuracy']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
