#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import numpy as np
import pytest

def test_fixed_output_exists():
    output_path = '/home/user/fixed_output.json'
    assert os.path.isfile(output_path), f"Output file is missing at {output_path}. Did you save the results?"

def test_output_mse_within_threshold():
    output_path = '/home/user/fixed_output.json'
    reference_path = '/tests/expected_reference.json'

    assert os.path.isfile(output_path), f"Output file is missing at {output_path}."
    assert os.path.isfile(reference_path), f"Reference file is missing at {reference_path}."

    try:
        with open(output_path, 'r') as f:
            agent_out = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Failed to parse JSON from {output_path}.")

    try:
        with open(reference_path, 'r') as f:
            reference = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Failed to parse JSON from {reference_path}.")

    assert isinstance(agent_out, list), f"Expected output to be a JSON list, got {type(agent_out).__name__}"
    assert len(agent_out) == len(reference), f"Length mismatch: agent produced {len(agent_out)} elements, expected {len(reference)} elements."

    # Calculate MSE
    agent_array = np.array(agent_out, dtype=np.float64)
    ref_array = np.array(reference, dtype=np.float64)

    mse = np.mean((agent_array - ref_array) ** 2)

    threshold = 1e-4
    assert mse <= threshold, f"MSE is too high: {mse} > {threshold}. The output does not match the expected precision or order."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
