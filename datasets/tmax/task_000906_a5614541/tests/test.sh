#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import signal
import subprocess
import time
from urllib.parse import urlparse

import numpy as np
import pandas as pd
import pytest
import requests
from sklearn.linear_model import Ridge
from sklearn.model_selection import KFold, cross_val_score


def _stop_existing_services():
    subprocess.run(["pkill", "-f", "/app/worker.py"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "uvicorn report:app"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "redis-server"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)


def _matching_process_environments():
    found = {}
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                cmdline = f.read().replace(b'\0', b' ').decode(errors='replace')
            role = None
            if '/app/worker.py' in cmdline:
                role = 'worker'
            elif 'uvicorn' in cmdline and 'report:app' in cmdline:
                role = 'report'
            if role is None:
                continue
            with open(f'/proc/{entry}/environ', 'rb') as f:
                entries = f.read().split(b'\0')
            env = {}
            for item in entries:
                if b'=' in item:
                    key, value = item.split(b'=', 1)
                    env[key.decode(errors='replace')] = value.decode(errors='replace')
            found[role] = env
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


@pytest.fixture(scope='session')
def running_services():
    assert os.path.isfile('/app/start.sh'), '/app/start.sh is missing'
    assert os.access('/app/start.sh', os.X_OK), '/app/start.sh is not executable'

    with open('/app/config.json') as f:
        config = json.load(f)
    assert config.get('REDIS_HOST') in ('127.0.0.1', 'localhost'), 'REDIS_HOST must point to local Redis'
    assert config.get('REDIS_PORT') == 6379, 'REDIS_PORT must be 6379'
    assert config.get('REDIS_PASS') == 'stat-sec-99', 'REDIS_PASS is incorrect'

    _stop_existing_services()
    log = open('/tmp/start-verifier.log', 'w+')
    proc = subprocess.Popen(['/app/start.sh'], stdout=log, stderr=subprocess.STDOUT,
                            start_new_session=True)

    session = requests.Session()
    ready = False
    for _ in range(30):
        if proc.poll() is not None:
            break
        try:
            worker = session.get('http://127.0.0.1:5001/', timeout=0.5)
            report = session.get('http://127.0.0.1:5002/report', timeout=0.5)
            if worker.status_code in (200, 404) and report.status_code in (200, 404):
                ready = True
                break
        except requests.RequestException:
            pass
        time.sleep(0.5)

    if not ready:
        log.flush()
        log.seek(0)
        pytest.fail('Services did not start via /app/start.sh. Output:\n' + log.read())

    environments = _matching_process_environments()
    assert 'worker' in environments, 'Worker was not launched by /app/start.sh'
    assert 'report' in environments, 'Report API was not launched by /app/start.sh'
    for role in ('worker', 'report'):
        redis_url = environments[role].get('REDIS_URL')
        assert redis_url, f'REDIS_URL was not exported to the {role} process'
        parsed = urlparse(redis_url)
        assert parsed.scheme == 'redis', f'Invalid REDIS_URL scheme for {role}'
        assert parsed.hostname in ('127.0.0.1', 'localhost'), f'Invalid REDIS_URL host for {role}'
        assert parsed.port == 6379, f'Invalid REDIS_URL port for {role}'
        assert parsed.password == 'stat-sec-99', f'REDIS_URL lacks the required password for {role}'
        assert parsed.path == '/0', f'REDIS_URL must select database 0 for {role}'

    yield session

    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    subprocess.run(['redis-cli', '-p', '6379', '-a', 'stat-sec-99', 'shutdown', 'nosave'],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    log.close()


def _expected_results(df):
    df_encoded = pd.get_dummies(df, columns=['category'])
    X = df_encoded.drop(columns=['target'])
    y = df_encoded['target']
    expected_corr = X.corr(method='pearson').to_dict()
    kf = KFold(n_splits=5, shuffle=True, random_state=42)
    model = Ridge(alpha=1.0)
    expected_cv_score = float(cross_val_score(model, X, y, cv=kf, scoring='r2').mean())
    return expected_cv_score, expected_corr


def _exercise_pipeline(session, df, filename):
    expected_cv_score, expected_corr = _expected_results(df)
    csv_buffer = io.StringIO()
    df.to_csv(csv_buffer, index=False)

    try:
        post_response = session.post(
            'http://127.0.0.1:5001/process',
            files={'file': (filename, csv_buffer.getvalue().encode('utf-8'), 'text/csv')},
            timeout=20,
        )
    except requests.exceptions.ConnectionError:
        pytest.fail('Failed to connect to Worker API on port 5001.')
    assert post_response.status_code == 200, (
        f'Worker API POST /process failed with status {post_response.status_code}: '
        f'{post_response.text}'
    )

    time.sleep(0.2)
    try:
        get_response = session.get('http://127.0.0.1:5002/report', timeout=10)
    except requests.exceptions.ConnectionError:
        pytest.fail('Failed to connect to Report API on port 5002.')
    assert get_response.status_code == 200, (
        f'Report API GET /report failed with status {get_response.status_code}: '
        f'{get_response.text}'
    )

    data = get_response.json()
    assert 'cv_score' in data, "Response JSON is missing 'cv_score'"
    assert 'correlation_matrix' in data, "Response JSON is missing 'correlation_matrix'"

    actual_cv_score = data['cv_score']
    assert isinstance(actual_cv_score, (float, int)), (
        f'Expected cv_score to be a number, got {type(actual_cv_score)}'
    )
    assert abs(actual_cv_score - expected_cv_score) < 1e-4, (
        f'cv_score mismatch. Expected {expected_cv_score}, got {actual_cv_score}. '
        'Check random_state=42 and Ridge(alpha=1.0).'
    )

    actual_corr = data['correlation_matrix']
    assert isinstance(actual_corr, dict), 'correlation_matrix should be a nested dictionary'
    for k1, v1 in expected_corr.items():
        assert k1 in actual_corr, f'Feature {k1} missing from correlation matrix'
        for k2, v2 in v1.items():
            assert k2 in actual_corr[k1], f'Feature {k2} missing from correlation matrix[{k1}]'
            actual_val = actual_corr[k1][k2]
            if pd.isna(v2):
                assert pd.isna(actual_val) or actual_val is None, (
                    f'Expected NaN for corr({k1}, {k2}), got {actual_val}'
                )
            else:
                assert abs(actual_val - v2) < 1e-4, (
                    f'Correlation mismatch for {k1} and {k2}. Expected {v2}, got {actual_val}'
                )


def test_pipeline_end_to_end(running_services):
    # Preserve the original deterministic regression check.
    rng = np.random.RandomState(123)
    n_samples = 100
    fixed_df = pd.DataFrame({
        'feature_1': rng.randn(n_samples),
        'feature_2': rng.randn(n_samples) * 2 + 1,
        'category': rng.choice(['A', 'B', 'C'], size=n_samples),
        'target': rng.randn(n_samples) * 5,
    })
    _exercise_pipeline(running_services, fixed_df, 'fixed.csv')

    # Runtime-randomized inputs prevent returning results hardcoded for the fixed fixture.
    for index, n_samples in enumerate((83, 117)):
        seed = int.from_bytes(os.urandom(8), 'big')
        random_rng = np.random.default_rng(seed)
        categories = random_rng.choice(['A', 'B', 'C'], size=n_samples)
        categories[:3] = ['A', 'B', 'C']
        randomized_df = pd.DataFrame({
            'feature_1': random_rng.normal(loc=index * 0.7, scale=1.1, size=n_samples),
            'feature_2': random_rng.normal(loc=-1.5 + index, scale=2.3, size=n_samples),
            'category': categories,
            'target': random_rng.normal(loc=2.0 - index, scale=4.2, size=n_samples),
        })
        _exercise_pipeline(running_services, randomized_df, f'random-{seed}.csv')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
