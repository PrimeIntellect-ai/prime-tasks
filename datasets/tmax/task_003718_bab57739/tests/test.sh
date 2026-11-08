#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

# Supply clean instances of the services needed to exercise the submitted workflow.
redis-cli -p 6379 shutdown >/dev/null 2>&1 || true
pkill -f '^python3 /app/data_api.py$' >/dev/null 2>&1 || true
redis-server --daemonize yes
REDIS_URL=redis://127.0.0.1:6379/0 python3 /app/data_api.py >/tmp/verifier_data_api.log 2>&1 &
API_PID=$!
trap 'kill "$API_PID" >/dev/null 2>&1 || true; redis-cli -p 6379 shutdown >/dev/null 2>&1 || true' EXIT

for _ in $(seq 1 50); do
    if curl -fsS http://127.0.0.1:5000/data >/dev/null 2>&1; then
        break
    fi
    # A 400 response means Flask is ready but no dataset has been generated yet.
    code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:5000/data || true)
    [ "$code" = "400" ] && break
    sleep 0.2
done

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import re
import secrets
import stat
import subprocess
import urllib.request

import numpy as np
from scipy.special import logsumexp

ESTIMATE = '/home/user/estimate.py'
PIPELINE = '/home/user/run_pipeline.sh'
RAW = '/home/user/raw_data.json'
METRICS = '/home/user/final_metrics.json'


def run_as_user(command, timeout):
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', 'timeout', str(timeout)] + command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert result.returncode == 0, (
        f"Command failed with status {result.returncode}: {' '.join(command)}\n"
        f"{result.stdout[-6000:]}"
    )


def read_metrics():
    assert os.path.isfile(METRICS), 'The file /home/user/final_metrics.json does not exist.'
    with open(METRICS, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError('The file /home/user/final_metrics.json is not valid JSON.') from exc

    for key in ('posterior_mean', 'ci_lower', 'ci_upper'):
        assert key in data, f"Missing '{key}' in final_metrics.json"
        assert type(data[key]) in (int, float), f"'{key}' must be a number"
        assert math.isfinite(data[key]), f"'{key}' must be finite"
    assert data['ci_lower'] <= data['ci_upper'], 'Bootstrap CI bounds are reversed'
    return data


def posterior_mean_reference(values):
    """Numerically integrate the specified one-dimensional posterior."""
    x = np.asarray(values, dtype=float)
    grid = np.linspace(-10.0, 10.0, 10001)
    log_post = np.empty(grid.size)
    log_norm_weight = math.log(0.7) - math.log(2.0 * math.sqrt(2.0 * math.pi))
    log_uniform_weight = math.log(0.3 / 30.0)
    uniform_ok = (x >= -15.0) & (x <= 15.0)

    for start in range(0, grid.size, 250):
        g = grid[start:start + 250, None]
        log_gaussian = log_norm_weight - 0.5 * ((x[None, :] - g) / 2.0) ** 2
        log_uniform = np.where(uniform_ok[None, :], log_uniform_weight, -np.inf)
        log_likelihood = np.logaddexp(log_gaussian, log_uniform).sum(axis=1)
        log_post[start:start + len(g)] = log_likelihood - 0.5 * (g[:, 0] / 10.0) ** 2

    weights = np.exp(log_post - logsumexp(log_post))
    return float(np.dot(grid, weights))


def test_01_required_artifacts_and_methods_exist():
    assert os.path.isfile(ESTIMATE), 'Missing /home/user/estimate.py'
    assert stat.S_ISREG(os.stat(ESTIMATE).st_mode), 'estimate.py must be a regular file'
    assert os.path.isfile(PIPELINE), 'Missing /home/user/run_pipeline.sh'
    assert stat.S_ISREG(os.stat(PIPELINE).st_mode), 'run_pipeline.sh must be a regular file'

    with open(ESTIMATE, 'r', errors='replace') as f:
        source = f.read().lower()
    with open(PIPELINE, 'r', errors='replace') as f:
        pipeline_source = f.read()

    assert re.search(r'\b(mcmc|metropolis(?:-hastings)?)\b', source), 'estimate.py does not contain an MCMC implementation'
    assert 'bootstrap' in source, 'estimate.py does not contain bootstrap logic'
    assert re.search(r'\bburn(?:[_ -]?in)?\b', source), 'estimate.py does not implement/discuss burn-in'
    assert re.search(r'\b(accept|acceptance)\w*\b', source), 'estimate.py lacks an MCMC acceptance step'
    integers = [int(v.replace('_', '')) for v in re.findall(r'(?<![\w.])\d[\d_]*(?![\w.])', source)]
    assert any(v >= 1000 for v in integers), 'At least 1,000 bootstrap resamples are required'
    assert pipeline_source.startswith('#!') or 'python' in pipeline_source, 'run_pipeline.sh is not a usable shell workflow'


def test_02_estimator_on_unseen_derived_data():
    # Use a fresh, unpredictable parameter so a file containing the exposed 4.2
    # cannot pass. The expected answer is derived independently from the data.
    rng = np.random.default_rng(secrets.randbits(128))
    hidden_mu = float(rng.uniform(-3.0, 6.0))
    while abs(hidden_mu - 4.2) < 0.8:
        hidden_mu = float(rng.uniform(-3.0, 6.0))

    n = 1800
    mask = rng.random(n) < 0.7
    values = np.where(mask, rng.normal(hidden_mu, 2.0, n), rng.uniform(-15.0, 15.0, n))
    with open(RAW, 'w') as f:
        json.dump(values.tolist(), f)
    before = hashlib.sha256(open(RAW, 'rb').read()).hexdigest()
    if os.path.exists(METRICS):
        os.remove(METRICS)

    expected = posterior_mean_reference(values)
    run_as_user(['python3', ESTIMATE], 240)
    after = hashlib.sha256(open(RAW, 'rb').read()).hexdigest()
    assert after == before, 'estimate.py replaced or modified its input dataset'

    result = read_metrics()
    assert abs(result['posterior_mean'] - expected) <= 0.20, (
        f"Posterior mean {result['posterior_mean']} disagrees with independently "
        f"computed posterior mean {expected}"
    )
    assert result['ci_lower'] <= result['posterior_mean'] <= result['ci_upper'], (
        'Bootstrap confidence interval does not contain the reported posterior mean'
    )
    assert 1e-7 < result['ci_upper'] - result['ci_lower'] < 1.0, (
        'Bootstrap confidence interval is degenerate or implausibly wide'
    )


def test_03_pipeline_and_original_metrics_assertions():
    subprocess.run(['redis-cli', '-p', '6379', 'FLUSHALL'], check=True, stdout=subprocess.DEVNULL)
    for path in (RAW, METRICS):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    run_as_user(['bash', PIPELINE], 300)

    assert os.path.isfile(RAW), 'run_pipeline.sh did not create /home/user/raw_data.json'
    with open(RAW, 'r') as f:
        raw = json.load(f)
    assert isinstance(raw, list) and len(raw) == 1500, 'raw_data.json is not the generated 1,500-point dataset'
    assert all(type(v) in (int, float) and math.isfinite(v) for v in raw), 'raw_data.json contains invalid values'

    # The local file must really be the dataset fetched from the live API.
    with urllib.request.urlopen('http://127.0.0.1:5000/data', timeout=5) as response:
        api_data = json.loads(response.read().decode('utf-8'))
    assert raw == api_data, 'raw_data.json does not match the dataset served by the API'

    data = read_metrics()
    mu_est = data['posterior_mean']
    ci_l = data['ci_lower']
    ci_u = data['ci_upper']

    # Preserve the original verifier's assertions.
    target_mu = 4.2
    error = abs(mu_est - target_mu)
    assert error <= 0.15, (
        f"Metric threshold exceeded. Absolute error {error:.4f} > 0.15. Estimated mu: {mu_est}"
    )
    assert ci_l <= target_mu <= ci_u, (
        f"True mu ({target_mu}) is not within the bootstrap CI [{ci_l}, {ci_u}]"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
