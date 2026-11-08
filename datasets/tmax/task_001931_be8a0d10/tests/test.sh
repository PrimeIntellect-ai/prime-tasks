#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math
import pytest

def test_analyze_go_exists():
    """Test that the Go source file was created."""
    file_path = "/home/user/analyze.go"
    assert os.path.isfile(file_path), f"The Go program {file_path} is missing."

def test_fit_results_exists():
    """Test that the JSON results file was created."""
    file_path = "/home/user/fit_results.json"
    assert os.path.isfile(file_path), f"The output file {file_path} is missing."

def test_fit_results_content():
    """Test that the JSON results file contains the correct KL divergence values."""
    results_path = "/home/user/fit_results.json"
    if not os.path.isfile(results_path):
        pytest.fail(f"Cannot check content because {results_path} is missing.")

    with open(results_path, 'r') as f:
        try:
            agent_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{results_path} is not valid JSON.")

    assert "kl_domain_a" in agent_data, "Key 'kl_domain_a' missing in JSON."
    assert "kl_domain_b" in agent_data, "Key 'kl_domain_b' missing in JSON."

    # Rebuild the dataset based on the mathematical truth
    y = [10.0 + 5.0 * math.sin(x / 10.0) + 2.0 * math.cos(x / 3.0) for x in range(100)]

    # 1. Smooth the data
    y_smooth = [0.0] * 100
    y_smooth[0] = (y[0] + y[1]) / 2.0
    y_smooth[99] = (y[98] + y[99]) / 2.0
    for i in range(1, 99):
        y_smooth[i] = (y[i-1] + y[i] + y[i+1]) / 3.0

    # 2. Domain Decomposition
    domain_a = y_smooth[:50]
    domain_b = y_smooth[50:]

    # 3. Normalization
    sum_a = sum(domain_a)
    p_a = [v / sum_a for v in domain_a]

    sum_b = sum(domain_b)
    p_b = [v / sum_b for v in domain_b]

    # 4. KL Divergence
    q_a_val = 1.0 / len(domain_a)
    kl_a = sum(p * math.log(p / q_a_val) for p in p_a)

    q_b_val = 1.0 / len(domain_b)
    kl_b = sum(p * math.log(p / q_b_val) for p in p_b)

    # 5. Assert with tolerance
    assert abs(agent_data['kl_domain_a'] - kl_a) < 1e-5, \
        f"Expected kl_domain_a to be close to {kl_a}, got {agent_data['kl_domain_a']}"
    assert abs(agent_data['kl_domain_b'] - kl_b) < 1e-5, \
        f"Expected kl_domain_b to be close to {kl_b}, got {agent_data['kl_domain_b']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
