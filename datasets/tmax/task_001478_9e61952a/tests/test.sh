#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import stat
import subprocess
import time
import urllib.request

import numpy as np
import pandas as pd
import pytest
import redis
from dotenv import dotenv_values
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
from sklearn.preprocessing import StandardScaler

OUTPUT = '/home/user/model_input.parquet'
SCRIPT = '/home/user/prepare_data.py'
API_DATA = '/home/user/services/api/data.json'
HISTORICAL = '/home/user/storage/historical.parquet'
EXPECTED_CANDIDATES = []


def fetch_features():
    with urllib.request.urlopen('http://localhost:8080/api/features', timeout=5) as response:
        assert response.status == 200
        return json.loads(response.read().decode('utf-8'))


def process_is_running(fragment):
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        try:
            with open(f'/proc/{pid}/cmdline', 'rb') as f:
                cmdline = f.read().replace(b'\0', b' ').decode(errors='ignore')
            if fragment in cmdline:
                return True
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return False


def expected_outputs(rt_df, hist_df):
    joined = rt_df.merge(hist_df, on='user_id', how='inner')
    joined['support_tickets'] = joined['support_tickets'].fillna(joined['support_tickets'].median())
    threshold = joined['transaction_volume'].mean() + 3 * joined['transaction_volume'].std()
    joined = joined[joined['transaction_volume'] <= threshold].copy()
    features = joined[['session_duration', 'transaction_volume', 'support_tickets']]

    candidates = []
    population_scaled = StandardScaler().fit_transform(features)
    population_scores = PCA(n_components=2).fit_transform(population_scaled)
    candidates.append(pd.DataFrame({
        'pca_1': population_scores[:, 0],
        'pca_2': population_scores[:, 1],
        'churn': joined['churn'].to_numpy(),
    }))

    # Also accept standardization using the sample standard deviation. Both are
    # conventional interpretations of zero-mean, unit-variance standardization.
    sample_scaled = ((features - features.mean()) / features.std(ddof=1)).to_numpy()
    sample_scores = PCA(n_components=2).fit_transform(sample_scaled)
    candidates.append(pd.DataFrame({
        'pca_1': sample_scores[:, 0],
        'pca_2': sample_scores[:, 1],
        'churn': joined['churn'].to_numpy(),
    }))
    return candidates


def sorted_values(df):
    return df.sort_values(['churn', 'pca_1', 'pca_2']).reset_index(drop=True).to_numpy()


def test_service_configuration_and_running_stack():
    env = dotenv_values('/home/user/services/api/.env')
    assert env.get('REDIS_URL') == 'redis://localhost:6380/0', 'REDIS_URL must point to Redis on port 6380.'

    with open('/home/user/services/nginx/nginx.conf', 'r') as f:
        nginx_conf = f.read()
    assert re.search(r'proxy_pass\s+http://(?:127\.0\.0\.1|localhost):5000\s*;', nginx_conf), \
        'Nginx must proxy API requests to the Flask service on port 5000.'

    assert redis.Redis(host='localhost', port=6380, db=0, socket_connect_timeout=2).ping(), \
        'Redis is not running on port 6380.'
    assert process_is_running('app.py'), 'The Flask API process is not running.'
    assert process_is_running('nginx'), 'The Nginx process is not running.'
    initial = fetch_features()
    assert isinstance(initial, list) and initial, 'The API must return a non-empty JSON array.'
    assert {'user_id', 'session_duration', 'click_rate', 'churn'} <= set(initial[0]), \
        'API records do not contain the required fields.'


def test_prepare_data_executes_pipeline_on_fresh_inputs():
    global EXPECTED_CANDIDATES

    assert os.path.exists(SCRIPT), 'The file /home/user/prepare_data.py does not exist.'
    assert not os.path.islink(SCRIPT), 'prepare_data.py must be a regular Python script, not a symlink.'
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), 'prepare_data.py is not a regular file.'

    rng = np.random.default_rng(secrets.randbits(64))
    common_ids = rng.choice(np.arange(10000, 90000), size=180, replace=False)
    rt_extra = rng.choice(np.arange(100000, 110000), size=7, replace=False)
    hist_extra = rng.choice(np.arange(120000, 130000), size=9, replace=False)
    churn = rng.integers(0, 2, size=len(common_ids), dtype=np.int64)

    session = np.where(churn == 0, rng.normal(110, 8, len(common_ids)), rng.normal(40, 8, len(common_ids)))
    click = session * 0.55 + rng.normal(0, 1.5, len(common_ids))
    transaction = np.where(churn == 0, rng.normal(600, 35, len(common_ids)), rng.normal(150, 35, len(common_ids)))
    tickets = np.where(churn == 0, rng.normal(1, 0.5, len(common_ids)), rng.normal(7, 0.5, len(common_ids))).astype(float)

    outlier_positions = rng.choice(len(common_ids), size=4, replace=False)
    transaction[outlier_positions] = 6000 + rng.normal(0, 20, size=4)
    missing_positions = rng.choice(len(common_ids), size=13, replace=False)
    tickets[missing_positions] = np.nan

    rt_common = pd.DataFrame({
        'user_id': common_ids.astype(int),
        'session_duration': session,
        'click_rate': click,
        'churn': churn.astype(int),
    })
    rt_extra_df = pd.DataFrame({
        'user_id': rt_extra.astype(int),
        'session_duration': rng.normal(75, 10, len(rt_extra)),
        'click_rate': rng.normal(35, 5, len(rt_extra)),
        'churn': rng.integers(0, 2, len(rt_extra)).astype(int),
    })
    rt_df = pd.concat([rt_common, rt_extra_df], ignore_index=True).sample(frac=1, random_state=int(rng.integers(0, 2**31))).reset_index(drop=True)

    hist_common = pd.DataFrame({
        'user_id': common_ids.astype(int),
        'transaction_volume': transaction,
        'support_tickets': tickets,
    })
    hist_extra_df = pd.DataFrame({
        'user_id': hist_extra.astype(int),
        'transaction_volume': rng.normal(350, 40, len(hist_extra)),
        'support_tickets': rng.normal(3, 1, len(hist_extra)),
    })
    hist_df = pd.concat([hist_common, hist_extra_df], ignore_index=True).sample(frac=1, random_state=int(rng.integers(0, 2**31))).reset_index(drop=True)

    with open(API_DATA, 'w') as f:
        json.dump(rt_df.to_dict(orient='records'), f)
    hist_df.to_parquet(HISTORICAL, index=False)

    served = pd.DataFrame(fetch_features()).sort_values('user_id').reset_index(drop=True)
    wanted = rt_df.sort_values('user_id').reset_index(drop=True)
    assert list(served.columns) == list(wanted.columns)
    assert np.array_equal(served['user_id'].to_numpy(), wanted['user_id'].to_numpy())
    assert np.array_equal(served['churn'].to_numpy(), wanted['churn'].to_numpy())
    assert np.allclose(served[['session_duration', 'click_rate']], wanted[['session_duration', 'click_rate']], rtol=1e-12, atol=1e-12)

    EXPECTED_CANDIDATES = expected_outputs(rt_df, hist_df)
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ['python3', SCRIPT], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert result.returncode == 0, f'prepare_data.py failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    assert os.path.isfile(OUTPUT), 'Running prepare_data.py did not generate model_input.parquet.'

    actual = pd.read_parquet(OUTPUT)
    assert list(actual.columns) == ['pca_1', 'pca_2', 'churn']
    assert len(actual) == len(EXPECTED_CANDIDATES[0]), 'Output has the wrong number of joined/filtered rows.'
    assert np.isfinite(actual[['pca_1', 'pca_2']].to_numpy()).all(), 'PCA output contains non-finite values.'

    matched = False
    for expected in EXPECTED_CANDIDATES:
        for sign1 in (-1, 1):
            for sign2 in (-1, 1):
                adjusted = actual.copy()
                adjusted['pca_1'] *= sign1
                adjusted['pca_2'] *= sign2
                if np.allclose(sorted_values(adjusted), sorted_values(expected), rtol=2e-5, atol=2e-5):
                    matched = True
                    break
            if matched:
                break
        if matched:
            break
    assert matched, 'Output does not match the required join, imputation, outlier filtering, standardization, and two-component PCA pipeline.'


def test_model_input_parquet_exists():
    assert os.path.isfile('/home/user/model_input.parquet'), 'The file /home/user/model_input.parquet does not exist.'


def test_model_input_columns():
    df = pd.read_parquet('/home/user/model_input.parquet')
    expected_columns = ['pca_1', 'pca_2', 'churn']
    assert list(df.columns) == expected_columns, f'Columns in parquet file do not match exactly. Expected {expected_columns}, got {list(df.columns)}.'


def test_logistic_regression_accuracy():
    df = pd.read_parquet('/home/user/model_input.parquet')
    X = df[['pca_1', 'pca_2']]
    y = df['churn']

    model = LogisticRegression(random_state=42)
    model.fit(X, y)
    preds = model.predict(X)
    acc = accuracy_score(y, preds)

    assert acc >= 0.80, f'Logistic Regression accuracy is {acc}, which is below the required threshold of 0.80.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
