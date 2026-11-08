#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest
import subprocess
import sys
import tempfile

def get_expected_values():
    """
    Computes the expected values by running the ground truth logic
    in a subprocess to avoid importing third-party libraries directly
    in the test file (adhering to stdlib-only rule for the test itself).
    """
    script = """
import numpy as np
import json
from scipy.integrate import odeint

data = np.loadtxt('/home/user/observations.csv', delimiter=',', skiprows=1)
t = data[:, 0]
I_obs = data[:, 1]

def sir_model(y, t, beta, gamma):
    S, I, R = y
    return [-beta*S*I, beta*S*I - gamma*I, gamma*I]

def log_likelihood(beta, gamma):
    try:
        res = odeint(sir_model, [0.99, 0.01, 0.0], t, args=(beta, gamma))
        I_pred = res[:, 1]
        sse = np.sum((I_obs - I_pred)**2)
        return -sse
    except:
        return -np.inf

np.random.seed(42)
beta_curr, gamma_curr = 0.5, 0.1
ll_curr = log_likelihood(beta_curr, gamma_curr)

beta_samples = []
gamma_samples = []

for _ in range(5000):
    beta_prop = np.random.normal(beta_curr, 0.05)
    gamma_prop = np.random.normal(gamma_curr, 0.05)

    if 0.1 <= beta_prop <= 2.0 and 0.01 <= gamma_prop <= 1.0:
        ll_prop = log_likelihood(beta_prop, gamma_prop)
        accept_prob = np.exp(ll_prop - ll_curr)
    else:
        accept_prob = 0
        ll_prop = -np.inf

    u = np.random.uniform()
    if u < accept_prob:
        beta_curr, gamma_curr = beta_prop, gamma_prop
        ll_curr = ll_prop

    beta_samples.append(beta_curr)
    gamma_samples.append(gamma_curr)

beta_post = np.array(beta_samples[1000:])
gamma_post = np.array(gamma_samples[1000:])

np.random.seed(123)
R0 = beta_post / gamma_post
boot_means = []
for _ in range(10000):
    resample = np.random.choice(R0, size=len(R0), replace=True)
    boot_means.append(np.mean(resample))

output = {
    "beta_mean": float(np.mean(beta_post)),
    "gamma_mean": float(np.mean(gamma_post)),
    "R0_ci_lower": float(np.percentile(boot_means, 2.5)),
    "R0_ci_upper": float(np.percentile(boot_means, 97.5))
}

print(json.dumps(output))
"""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write(script)
        temp_path = f.name

    try:
        result = subprocess.run([sys.executable, temp_path], capture_output=True, text=True, check=True)
        return json.loads(result.stdout.strip())
    finally:
        os.remove(temp_path)

def test_training_meta_exists():
    """Test that the training_meta.json file exists."""
    file_path = '/home/user/training_meta.json'
    assert os.path.exists(file_path), f"The output file {file_path} is missing."
    assert os.path.isfile(file_path), f"The path {file_path} exists but is not a file."

def test_training_meta_format_and_values():
    """Test that the training_meta.json has correct keys and values."""
    file_path = '/home/user/training_meta.json'

    with open(file_path, 'r') as f:
        try:
            student_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} does not contain valid JSON.")

    expected_keys = {"beta_mean", "gamma_mean", "R0_ci_lower", "R0_ci_upper"}
    actual_keys = set(student_data.keys())

    assert expected_keys.issubset(actual_keys), f"Missing keys in JSON. Expected {expected_keys}, found {actual_keys}."

    for key in expected_keys:
        assert isinstance(student_data[key], float), f"Value for {key} must be a float, got {type(student_data[key])}."

    expected_data = get_expected_values()

    for key in expected_keys:
        student_val = student_data[key]
        expected_val = expected_data[key]
        assert abs(student_val - expected_val) <= 1e-4, \
            f"Value for {key} is incorrect. Expected ~{expected_val:.5f}, got {student_val:.5f}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
