#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import numpy as np

def test_result_rmse():
    result_path = '/home/user/result.csv'

    assert os.path.isfile(result_path), f"Output file {result_path} does not exist."

    # Recompute ground truth
    np.random.seed(42)
    num_records = 1000000
    dim = 10
    threshold = 15.2

    data = np.random.normal(0, 5.0, (num_records, dim))
    norms = np.linalg.norm(data, axis=1)
    valid_data = data[norms <= threshold]
    true_mean = np.mean(valid_data, axis=0)

    # Read agent's output
    try:
        agent_data = np.loadtxt(result_path, delimiter=',')
    except Exception as e:
        assert False, f"Failed to read {result_path} as CSV: {e}"

    assert agent_data.shape == (10,), f"Expected 10-dimensional vector, got shape {agent_data.shape}"

    # Calculate RMSE
    rmse = np.sqrt(np.mean((agent_data - true_mean)**2))

    # Assert threshold
    assert rmse <= 0.001, f"RMSE {rmse} is greater than the allowed threshold of 0.001."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
