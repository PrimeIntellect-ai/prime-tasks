#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import numpy as np

def test_final_parameters():
    results_path = "/home/user/results/params.json"
    assert os.path.isfile(results_path), f"Results file not found: {results_path}"

    with open(results_path, 'r') as f:
        try:
            params = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {results_path} is not valid JSON."

    for key in ['k1', 'k2', 'A0']:
        assert key in params, f"Missing key '{key}' in {results_path}"

    k1 = params['k1']
    k2 = params['k2']
    A0 = params['A0']

    assert isinstance(k1, (int, float)), "k1 must be a number"
    assert isinstance(k2, (int, float)), "k2 must be a number"
    assert isinstance(A0, (int, float)), "A0 must be a number"

    true_k1 = 0.85
    true_k2 = 0.15
    true_A0 = 10.0

    err_k1 = (k1 - true_k1) / true_k1
    err_k2 = (k2 - true_k2) / true_k2
    err_A0 = (A0 - true_A0) / true_A0

    mse = np.mean([err_k1**2, err_k2**2, err_A0**2])

    threshold = 0.01
    assert mse <= threshold, (
        f"MSE of normalized parameters is {mse:.6f}, which exceeds the threshold of {threshold}. "
        f"Parameters found: k1={k1}, k2={k2}, A0={A0}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
