#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import math
import os
import secrets
import stat
import subprocess

import numpy as np
import pandas as pd
from sklearn.linear_model import RidgeCV

SCRIPT_PATH = '/home/user/etl_pipeline.py'
DATA_PATH = '/home/user/sensor_data.csv'
METRICS_PATH = '/home/user/model_metrics.json'
ALPHAS = [0.01, 0.1, 1.0, 10.0, 100.0]


def expected_metrics(csv_bytes):
    df = pd.read_csv(io.BytesIO(csv_bytes))
    df = df[
        df['temp'].between(-50.0, 50.0, inclusive='both')
        & df['humidity'].between(0.0, 100.0, inclusive='both')
        & (df['pressure'] > 0)
    ].dropna()

    np.random.seed(42)
    X = df[['temp', 'pressure', 'humidity']]
    y = df['error_margin']
    model = RidgeCV(alphas=ALPHAS, cv=5)
    model.fit(X, y)
    return float(model.alpha_), round(float(model.score(X, y)), 4)


def run_and_check(csv_bytes):
    expected_alpha, expected_r2 = expected_metrics(csv_bytes)
    with open(DATA_PATH, 'wb') as f:
        f.write(csv_bytes)

    if os.path.lexists(METRICS_PATH):
        os.remove(METRICS_PATH)

    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'etl_pipeline.py failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )

    assert os.path.exists(METRICS_PATH), (
        f'The file {METRICS_PATH} does not exist. Did you save the output?'
    )
    assert os.path.isfile(METRICS_PATH), f'The path {METRICS_PATH} is not a file.'

    try:
        with open(METRICS_PATH, 'r') as f:
            metrics = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'The file {METRICS_PATH} is not valid JSON.') from exc

    assert isinstance(metrics, dict), 'The metrics JSON must contain an object.'
    assert 'best_alpha' in metrics, "The key 'best_alpha' is missing from the JSON file."
    assert 'r2_score' in metrics, "The key 'r2_score' is missing from the JSON file."
    assert set(metrics) == {'best_alpha', 'r2_score'}, (
        "The JSON object must contain exactly 'best_alpha' and 'r2_score'."
    )

    actual_alpha = metrics['best_alpha']
    assert isinstance(actual_alpha, (int, float)) and not isinstance(actual_alpha, bool), (
        "'best_alpha' must be a number."
    )
    assert math.isclose(actual_alpha, expected_alpha, rel_tol=1e-4), (
        f'Expected best_alpha to be {expected_alpha}, got {actual_alpha}. '
        'Check your cross-validation setup.'
    )

    actual_r2 = metrics['r2_score']
    assert isinstance(actual_r2, (int, float)) and not isinstance(actual_r2, bool), (
        "'r2_score' must be a number."
    )
    assert math.isclose(actual_r2, expected_r2, abs_tol=1e-2), (
        f'Expected r2_score to be approximately {expected_r2}, got {actual_r2}. '
        'Check your data filtering and random seed.'
    )
    assert actual_r2 == expected_r2, (
        f'Expected the in-sample R2 rounded to 4 decimal places ({expected_r2}), '
        f'got {actual_r2}.'
    )


def make_challenge_data():
    rng = np.random.default_rng(secrets.randbits(64))
    n = 137
    temp = rng.uniform(-48.0, 48.0, n)
    pressure = rng.uniform(700.0, 1250.0, n)
    humidity = rng.uniform(1.0, 99.0, n)
    error = (
        0.37 * temp
        - 0.083 * pressure
        + 0.24 * humidity
        + rng.normal(0.0, 6.0, n)
    )
    df = pd.DataFrame({
        'temp': temp,
        'pressure': pressure,
        'humidity': humidity,
        'error_margin': error,
    })

    # Violations and NaNs must be discarded; boundary values remain valid.
    df.loc[0, ['temp', 'error_margin']] = [100.0, 1_000_000.0]
    df.loc[1, ['humidity', 'error_margin']] = [-10.0, -1_000_000.0]
    df.loc[2, ['pressure', 'error_margin']] = [-5.0, 750_000.0]
    df.loc[3, 'temp'] = np.nan
    df.loc[4, 'error_margin'] = np.nan
    df.loc[5, ['temp', 'humidity', 'pressure']] = [-50.0, 0.0, 0.1]
    df.loc[6, ['temp', 'humidity']] = [50.0, 100.0]
    return df.to_csv(index=False).encode()


def test_pipeline_script_and_outputs():
    assert os.path.exists(SCRIPT_PATH), f'The file {SCRIPT_PATH} does not exist.'
    assert os.path.isfile(SCRIPT_PATH), f'The path {SCRIPT_PATH} is not a file.'
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), (
        f'The path {SCRIPT_PATH} must be a regular Python script.'
    )

    with open(DATA_PATH, 'rb') as f:
        original_data = f.read()

    try:
        # Check the required supplied dataset, then exercise the same pipeline on
        # an unpredictable dataset so a pre-fabricated metrics file cannot pass.
        run_and_check(original_data)
        run_and_check(make_challenge_data())
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_data)
        if os.path.isfile(SCRIPT_PATH):
            if os.path.lexists(METRICS_PATH):
                os.remove(METRICS_PATH)
            subprocess.run(
                ['python3', SCRIPT_PATH],
                cwd='/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=120,
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
