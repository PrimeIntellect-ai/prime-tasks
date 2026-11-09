#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import numpy as np
from scipy.stats import gaussian_kde

def test_mcmc_results():
    data_path = '/home/user/data.txt'
    assert os.path.exists(data_path), f"Data file {data_path} is missing."

    with open(data_path, 'r') as f:
        data = np.array([int(line.strip()) for line in f])
    N = len(data)
    sum_x = np.sum(data)

    def log_post(lam):
        if lam <= 0:
            return -np.inf
        return np.log(lam) * sum_x - N * lam

    expected_samples = []
    for rank in range(4):
        np.random.seed(rank * 100)
        lam = 5.0
        samples = []
        for _ in range(5000):
            prop = lam + np.random.normal(0, 0.5)
            if prop > 0:
                log_alpha = log_post(prop) - log_post(lam)
                u = np.random.uniform()
                if np.log(u) < log_alpha:
                    lam = prop
            samples.append(lam)
        expected_samples.extend(samples[1000:])

    expected_samples = np.array(expected_samples)

    # Compute expected MAP estimate
    kde = gaussian_kde(expected_samples)
    grid = np.linspace(0, 20, 1000)
    densities = kde(grid)
    expected_map = grid[np.argmax(densities)]
    expected_map_str = f"{expected_map:.2f}"

    # Validate samples.npy
    samples_path = '/home/user/samples.npy'
    assert os.path.exists(samples_path), f"Output file {samples_path} is missing. The script may not have saved the samples correctly."

    try:
        actual_samples = np.load(samples_path)
    except Exception as e:
        assert False, f"Failed to load {samples_path} as a NumPy array: {e}"

    assert actual_samples.shape == expected_samples.shape, f"Expected {expected_samples.shape[0]} total samples, got {actual_samples.shape[0]}."
    np.testing.assert_allclose(
        actual_samples, 
        expected_samples, 
        rtol=1e-5, 
        err_msg="The generated samples do not match the expected deterministic MCMC values. Ensure the random seed, proposal distribution, and acceptance criteria are exactly as specified."
    )

    # Validate map_lambda.txt
    map_path = '/home/user/map_lambda.txt'
    assert os.path.exists(map_path), f"Output file {map_path} is missing. The script may not have saved the MAP estimate."

    with open(map_path, 'r') as f:
        actual_map_str = f.read().strip()

    assert actual_map_str == expected_map_str, f"Expected MAP estimate '{expected_map_str}', but found '{actual_map_str}' in {map_path}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
