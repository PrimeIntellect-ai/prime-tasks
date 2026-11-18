#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import secrets
import urllib.error
import urllib.request

import pytest


def compute_expected_prediction(payload):
    file_path = '/home/user/system_metrics.csv'

    with open(file_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    # 1. Drop missing target
    valid_rows = [r for r in rows if r['is_anomaly'].strip() != '']

    # 2. Impute missing features with median
    features = ['cpu_load', 'disk_io', 'memory_usage', 'net_rx']
    medians = {}
    for feat in features:
        vals = [float(r[feat]) for r in valid_rows if r[feat].strip() != '']
        sorted_vals = sorted(vals)
        n = len(sorted_vals)
        if n % 2 == 1:
            medians[feat] = sorted_vals[n // 2]
        else:
            medians[feat] = (sorted_vals[n // 2 - 1] + sorted_vals[n // 2]) / 2.0

    # Prepare dataset
    X = []
    y = []
    for r in valid_rows:
        row_feats = []
        for feat in features:
            val = r[feat].strip()
            row_feats.append(float(val) if val != '' else medians[feat])
        X.append(row_feats)
        y.append(int(float(r['is_anomaly'])))

    # 3. GaussianNB training
    classes = [0, 1]
    class_stats = {}
    var_max = 0.0

    for c in classes:
        X_c = [X[i] for i in range(len(X)) if y[i] == c]
        n_c = len(X_c)
        stats = []
        for j in range(len(features)):
            col_vals = [X_c[i][j] for i in range(n_c)]
            mean = sum(col_vals) / n_c
            var = sum((v - mean) ** 2 for v in col_vals) / n_c
            stats.append((mean, var))
            if var > var_max:
                var_max = var
        class_stats[c] = {'prior': n_c / len(X), 'stats': stats}

    # Apply variance smoothing
    epsilon = 1e-9 * var_max
    for c in classes:
        class_stats[c]['stats'] = [(m, v + epsilon) for m, v in class_stats[c]['stats']]

    # 4. Predict
    log_probs = {}
    for c in classes:
        lp = math.log(class_stats[c]['prior'])
        for j, feat in enumerate(features):
            x_val = payload[feat]
            mean, var = class_stats[c]['stats'][j]
            lp -= 0.5 * math.log(2 * math.pi * var)
            lp -= 0.5 * ((x_val - mean) ** 2) / var
        log_probs[c] = lp

    # Convert log probs to probabilities (softmax)
    max_lp = max(log_probs.values())
    sum_exp = sum(math.exp(lp - max_lp) for lp in log_probs.values())
    return math.exp(log_probs[1] - max_lp) / sum_exp


def request_and_check(payload):
    req = urllib.request.Request(
        'http://127.0.0.1:8080/predict',
        data=json.dumps(payload).encode('utf-8'),
        headers={'Content-Type': 'application/json'},
        method='POST'
    )

    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f'Expected status 200, got {response.status}'
            resp_body = response.read().decode('utf-8')
    except urllib.error.URLError as e:
        pytest.fail(f'Could not connect to Flask app or request failed: {e}')

    try:
        data = json.loads(resp_body)
    except json.JSONDecodeError:
        pytest.fail(f'Response is not valid JSON: {resp_body}')

    assert isinstance(data, dict), 'Response JSON must be an object.'
    assert set(data.keys()) == {'anomaly_probability', 'is_anomaly'}, (
        'Response must contain exactly the keys anomaly_probability and is_anomaly.'
    )

    expected_prob = compute_expected_prediction(payload)
    actual_prob = float(data['anomaly_probability'])
    actual_label = int(data['is_anomaly'])

    # Assert probability is close to the expected value recomputed from the dataset
    assert abs(actual_prob - expected_prob) < 0.05, (
        f'Expected anomaly_probability ~{expected_prob:.3f}, got {actual_prob}'
    )

    expected_label = 1 if expected_prob > 0.5 else 0
    assert actual_label == expected_label, (
        f'Expected is_anomaly to be {expected_label}, got {actual_label}'
    )


def test_serve_model_script_exists_and_is_python():
    path = '/home/user/serve_model.py'
    assert os.path.isfile(path), f'Missing required Python script: {path}'
    assert os.path.getsize(path) > 0, f'Required Python script is empty: {path}'
    with open(path, 'r', encoding='utf-8') as f:
        ast.parse(f.read(), filename=path)


def test_flask_service_running_and_predicting():
    # Preserve the original fixed request and its assertions.
    request_and_check({
        'cpu_load': 80.0,
        'disk_io': 110.0,
        'memory_usage': 70.0,
        'net_rx': 600.0
    })


def test_predictions_on_unpredictable_inputs():
    # Generate fresh candidates at verification time so a fixed response or a
    # lookup table for known verifier inputs cannot pass.
    rng = secrets.SystemRandom()
    candidates = []
    for _ in range(128):
        payload = {
            'cpu_load': rng.uniform(-20.0, 130.0),
            'disk_io': rng.uniform(-50.0, 250.0),
            'memory_usage': rng.uniform(-30.0, 160.0),
            'net_rx': rng.uniform(100.0, 900.0),
        }
        candidates.append((compute_expected_prediction(payload), payload))

    candidates.sort(key=lambda item: item[0])
    selected = [candidates[0], candidates[-1]]
    for target_probability in (0.1, 0.3, 0.5, 0.7, 0.9):
        selected.append(min(candidates, key=lambda item: abs(item[0] - target_probability)))

    seen = set()
    for _, payload in selected:
        identity = tuple(payload[name] for name in sorted(payload))
        if identity not in seen:
            seen.add(identity)
            request_and_check(payload)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
