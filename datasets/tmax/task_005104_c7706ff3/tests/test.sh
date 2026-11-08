#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import math
import os
import random
import re
import subprocess

import numpy as np
import pandas as pd
import pytest
import requests
from sklearn.linear_model import BayesianRidge


def get_expected_model_and_features():
    df = pd.read_csv('/home/user/data/server_metrics.csv')

    # Impute missing cpu_usage with median
    median_cpu = df['cpu_usage'].median()
    df['cpu_usage'] = df['cpu_usage'].fillna(median_cpu)

    # Remove disk_io > 1000
    df = df[df['disk_io'] <= 1000].copy()

    # Compute correlations
    corr = df.corr().abs()
    latency_corr = corr['latency'].drop('latency')
    top_2_features = latency_corr.nlargest(2).index.tolist()

    # Train Bayesian Ridge
    X = df[top_2_features]
    y = df['latency']
    model = BayesianRidge()
    model.fit(X, y)

    return model, top_2_features, df


def test_experiment_json():
    json_path = '/home/user/experiment.json'
    assert os.path.exists(json_path), f'File {json_path} does not exist.'

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {json_path} does not contain valid JSON.')

    assert 'alpha' in data, "Key 'alpha' missing from experiment.json."
    assert 'lambda' in data, "Key 'lambda' missing from experiment.json."
    assert set(data) == {'alpha', 'lambda'}, 'experiment.json must contain exactly alpha and lambda.'

    model, _, _ = get_expected_model_and_features()
    assert isinstance(data['alpha'], (int, float)) and not isinstance(data['alpha'], bool)
    assert isinstance(data['lambda'], (int, float)) and not isinstance(data['lambda'], bool)
    assert math.isfinite(data['alpha']) and math.isfinite(data['lambda'])
    assert np.isclose(data['alpha'], model.alpha_, rtol=1e-7, atol=1e-12), \
        f"alpha does not match the learned model: expected {model.alpha_}, got {data['alpha']}"
    assert np.isclose(data['lambda'], model.lambda_, rtol=1e-7, atol=1e-12), \
        f"lambda does not match the learned model: expected {model.lambda_}, got {data['lambda']}"


def test_vendored_bottle_is_repaired_and_installed():
    code = subprocess.run(
        ['python3', '-c', 'import os,bottle; print(os.path.realpath(bottle.__file__)); print(bottle.__version__)'],
        text=True, capture_output=True, timeout=10
    )
    assert code.returncode == 0, f'Installed bottle cannot be imported: {code.stderr}'
    lines = code.stdout.strip().splitlines()
    assert lines and lines[0].startswith('/app/bottle-0.12.25/'), \
        f'bottle is not installed from the required vendored directory: {lines}'
    assert len(lines) > 1 and lines[1] == '0.12.25', f'Unexpected bottle version: {lines}'

    # Exercise routing directly so merely making the file parse is insufficient.
    import bottle
    from wsgiref.util import setup_testing_defaults

    app = bottle.Bottle()

    @app.get('/verifier-routing-check')
    def routing_check():
        return {'routed': True}

    environ = {}
    setup_testing_defaults(environ)
    environ['REQUEST_METHOD'] = 'GET'
    environ['PATH_INFO'] = '/verifier-routing-check'
    environ['wsgi.input'] = io.BytesIO(b'')
    result = {}

    def start_response(status, headers, exc_info=None):
        result['status'] = status
        result['headers'] = headers

    body = b''.join(app(environ, start_response))
    assert result['status'].startswith('200'), result
    assert json.loads(body.decode()) == {'routed': True}


def _listener_pid():
    socket_inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local, state = fields[1], fields[3]
                    if int(local.rsplit(':', 1)[1], 16) == 8080 and state == '0A':
                        socket_inodes.add(fields[9])
        except OSError:
            pass

    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        fd_dir = f'/proc/{pid}/fd'
        try:
            for fd in os.listdir(fd_dir):
                target = os.readlink(os.path.join(fd_dir, fd))
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in socket_inodes:
                    return int(pid)
        except (OSError, PermissionError):
            continue
    return None


def test_listening_server_uses_bottle():
    pid = _listener_pid()
    assert pid is not None, 'No process is listening on port 8080.'

    with open(f'/proc/{pid}/cmdline', 'rb') as f:
        argv = [part.decode(errors='replace') for part in f.read().split(b'\0') if part]
    evidence = '\n'.join(argv)

    try:
        cwd = os.readlink(f'/proc/{pid}/cwd')
    except OSError:
        cwd = ''

    candidates = []
    for arg in argv:
        path = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
        if path.endswith('.py') and os.path.isfile(path):
            candidates.append(path)

    if '-m' in argv:
        index = argv.index('-m')
        if index + 1 < len(argv):
            module_path = os.path.join(cwd, *argv[index + 1].split('.')) + '.py'
            if os.path.isfile(module_path):
                candidates.append(module_path)

    for path in set(candidates):
        try:
            with open(path, errors='replace') as f:
                evidence += '\n' + f.read()
        except OSError:
            pass

    assert re.search(r'(^|\n)\s*(?:import\s+bottle\b|from\s+bottle\s+import\b)', evidence), \
        f'The process listening on 8080 does not show evidence of using bottle. Command: {argv}'
    assert re.search(r'\b(?:route|get|post|Bottle)\b', evidence), \
        'The listening server does not appear to define its routes with bottle.'


def test_health_endpoint():
    url = 'http://127.0.0.1:8080/health'
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Failed to connect to {url}: {e}')

    assert response.status_code == 200, f'Expected status code 200, got {response.status_code}'

    try:
        data = response.json()
    except ValueError:
        pytest.fail('Response from /health is not valid JSON.')

    assert data.get('status') == 'ok', f"Expected {{'status': 'ok'}}, got {data}"


def test_predict_endpoint():
    model, top_2_features, cleaned_df = get_expected_model_and_features()
    url = 'http://127.0.0.1:8080/predict'

    # Preserve the original fixed check and add unpredictable, independently
    # derived cases spanning the cleaned data ranges.
    payloads = [{top_2_features[0]: 50.0, top_2_features[1]: 50.0}]
    rng = random.SystemRandom()
    ranges = {
        feature: (float(cleaned_df[feature].min()), float(cleaned_df[feature].max()))
        for feature in top_2_features
    }
    for _ in range(9):
        payloads.append({
            feature: rng.uniform(ranges[feature][0], ranges[feature][1])
            for feature in top_2_features
        })

    for payload in payloads:
        expected_pred = float(model.predict(pd.DataFrame([payload], columns=top_2_features))[0])
        try:
            response = requests.post(url, json=payload, timeout=5)
        except requests.exceptions.RequestException as e:
            pytest.fail(f'Failed to connect to {url}: {e}')

        assert response.status_code == 200, f'Expected status code 200, got {response.status_code}'
        try:
            data = response.json()
        except ValueError:
            pytest.fail('Response from /predict is not valid JSON.')

        assert 'predicted_latency' in data, "Key 'predicted_latency' missing from response."
        predicted_latency = data['predicted_latency']
        assert isinstance(predicted_latency, (int, float)) and not isinstance(predicted_latency, bool), \
            'predicted_latency must be a number.'
        assert math.isfinite(predicted_latency), 'predicted_latency must be finite.'

        # Preserve the original tolerance while exercising many distinct inputs.
        assert abs(predicted_latency - expected_pred) < 1.0, \
            f'For payload {payload}, expected prediction around {expected_pred}, got {predicted_latency}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
