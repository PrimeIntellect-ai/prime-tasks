#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import time

import numpy as np
import pandas as pd
import pytest
import redis
import requests

PARAMS_FILE = "/home/user/best_params.json"
WORKER_DIR = "/app/worker"
HARNESS = "/tmp/integrator_harness"


def expected_p(t, k1, k2, k3):
    t = np.asarray(t, dtype=float)
    if abs(k2 - k1) < 1e-10:
        # Limit for k1 == k2: B(t) = 10*k1*t*exp(-k1*t).
        return 10.0 * k3 * (1.0 - np.exp(-k1*t) * (1.0 + k1*t)) / k1
    return (10.0 * k3 * k1 / (k2 - k1)) * (
        (1.0 - np.exp(-k1*t)) / k1
        - (1.0 - np.exp(-k2*t)) / k2
    )


def random_params():
    rng = secrets.SystemRandom()
    k1 = rng.uniform(0.15, 0.9)
    k2 = rng.uniform(1.1, 2.8)
    k3 = rng.uniform(0.2, 1.6)
    return {"k1": k1, "k2": k2, "k3": k3}


def validate_simulation(sim_data, params):
    assert isinstance(sim_data, dict), "Simulation result must be a JSON object."
    assert 't' in sim_data, "Simulation response missing 't' array."
    assert 'P' in sim_data, "Simulation response missing 'P' array."

    sim_t = np.asarray(sim_data['t'], dtype=float)
    sim_p = np.asarray(sim_data['P'], dtype=float)
    assert sim_t.ndim == 1 and sim_p.ndim == 1
    assert len(sim_t) == len(sim_p) and len(sim_t) >= 5
    assert np.all(np.isfinite(sim_t)) and np.all(np.isfinite(sim_p))
    assert abs(sim_t[0]) <= 1e-8
    assert np.all(np.diff(sim_t) > 0), "Simulation times must be strictly increasing."
    assert sim_t[-1] >= 9.0, "Simulation does not cover the requested time interval."

    expected = expected_p(sim_t, params['k1'], params['k2'], params['k3'])
    assert np.allclose(sim_p, expected, rtol=2e-3, atol=1e-2), (
        "Simulation does not satisfy the submitted ODE parameters."
    )
    return sim_t, sim_p


def build_integrator_harness():
    source = r'''
#include <iostream>
#include <string>
#include <cstdlib>
std::string integrate(double, double, double);
int main(int argc, char **argv) {
    if (argc != 4) return 2;
    std::cout << integrate(std::strtod(argv[1], nullptr),
                           std::strtod(argv[2], nullptr),
                           std::strtod(argv[3], nullptr));
    return 0;
}
'''
    with open('/tmp/integrator_harness.cpp', 'w') as f:
        f.write(source)
    subprocess.run([
        'g++', '-O2', '/tmp/integrator_harness.cpp',
        '/app/worker/integrator.cpp', '-o', HARNESS
    ], check=True, timeout=30)


def test_best_params_exists_and_valid():
    params_file = PARAMS_FILE
    assert os.path.isfile(params_file), f"Output file {params_file} is missing."

    with open(params_file, 'r') as f:
        try:
            params = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {params_file} is not valid JSON.")

    for key in ["k1", "k2", "k3"]:
        assert key in params, f"Key '{key}' missing from {params_file}."
        assert isinstance(params[key], (int, float)), f"Value for '{key}' must be a number."
        assert not isinstance(params[key], bool)
        assert np.isfinite(params[key]), f"Value for '{key}' must be finite."


def test_submitted_integrator_source_on_unseen_parameters():
    assert os.path.isfile('/app/worker/integrator.cpp')
    assert os.path.isfile('/app/worker/worker')
    assert os.access('/app/worker/worker', os.X_OK)
    assert os.path.getmtime('/app/worker/worker') >= os.path.getmtime('/app/worker/integrator.cpp'), (
        "The worker was not recompiled after integrator.cpp was changed."
    )

    build_integrator_harness()
    for _ in range(3):
        params = random_params()
        proc = subprocess.run([
            HARNESS, str(params['k1']), str(params['k2']), str(params['k3'])
        ], capture_output=True, text=True, check=True, timeout=10)
        try:
            result = json.loads(proc.stdout)
        except json.JSONDecodeError as exc:
            pytest.fail(f"integrate() did not return valid JSON: {exc}")
        validate_simulation(result, params)


def test_api_on_unseen_parameters():
    for _ in range(2):
        params = random_params()
        try:
            resp = requests.post('http://127.0.0.1:8000/simulate', json=params, timeout=15)
            resp.raise_for_status()
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to communicate with the API server: {e}")
        validate_simulation(resp.json(), params)


def test_worker_communicates_through_redis():
    try:
        client = redis.Redis(host='127.0.0.1', port=6379, decode_responses=True,
                             socket_connect_timeout=3, socket_timeout=3)
        client.ping()
    except Exception as exc:
        pytest.fail(f"Redis is not reachable on port 6379: {exc}")

    params = random_params()
    job_id = 'verify_' + secrets.token_hex(16)
    result_key = 'result_' + job_id
    client.delete(result_key)
    client.lpush('job_queue', f"{job_id} {params['k1']} {params['k2']} {params['k3']}")

    raw = None
    deadline = time.time() + 10
    while time.time() < deadline:
        raw = client.get(result_key)
        if raw is not None:
            break
        time.sleep(0.1)
    client.delete(result_key)
    assert raw is not None, "The C++ worker did not consume a Redis job on port 6379."
    try:
        result = json.loads(raw)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Worker returned invalid JSON through Redis: {exc}")
    validate_simulation(result, params)


def test_simulation_mse():
    params_file = PARAMS_FILE
    assert os.path.isfile(params_file), f"Output file {params_file} is missing."

    with open(params_file, 'r') as f:
        params = json.load(f)

    try:
        resp = requests.post("http://127.0.0.1:8000/simulate", json=params, timeout=15)
        resp.raise_for_status()
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to communicate with the API server at http://127.0.0.1:8000/simulate. Ensure services are running and the bug in the C++ worker is fixed. Error: {e}")

    sim_data = resp.json()
    assert 't' in sim_data, "Simulation response missing 't' array."
    assert 'P' in sim_data, "Simulation response missing 'P' array."

    obs_file = "/app/data/observed.csv"
    assert os.path.isfile(obs_file), f"Observed data file {obs_file} is missing."

    obs_df = pd.read_csv(obs_file)
    assert 't' in obs_df.columns and 'P' in obs_df.columns, "Observed data missing 't' or 'P' columns."

    sim_t = np.array(sim_data['t'])
    sim_P = np.array(sim_data['P'])

    # Interpolate simulation to observed timepoints
    sim_P_interp = np.interp(obs_df['t'].values, sim_t, sim_P)

    mse = np.mean((sim_P_interp - obs_df['P'].values)**2)
    threshold = 0.01

    assert mse <= threshold, f"MSE {mse:.6f} is greater than the threshold {threshold}. Parameters used: {params}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
