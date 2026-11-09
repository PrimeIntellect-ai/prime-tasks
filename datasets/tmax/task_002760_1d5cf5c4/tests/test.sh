#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_libkalman_compiled():
    lib_path = '/app/kalman-c-1.0/libkalman.a'
    assert os.path.exists(lib_path), f"Static library was not compiled at {lib_path}"

def test_cleaned_sensor_output_and_mse():
    agent_file = '/home/user/cleaned_sensor.txt'
    truth_file = '/tests/clean_reference.txt'

    assert os.path.exists(agent_file), f"Agent output file missing: {agent_file}"
    assert os.path.exists(truth_file), f"Truth file missing: {truth_file}"

    with open(agent_file, 'r') as f:
        agent_lines = f.readlines()

    try:
        agent_data = [float(x.strip()) for x in agent_lines if x.strip()]
    except ValueError as e:
        pytest.fail(f"Could not parse agent output as floats: {e}")

    with open(truth_file, 'r') as f:
        ref_data = [float(x.strip()) for x in f.readlines() if x.strip()]

    assert len(agent_data) == len(ref_data), f"Length mismatch: agent produced {len(agent_data)} lines, expected {len(ref_data)}"

    mse = sum((a - r) ** 2 for a, r in zip(agent_data, ref_data)) / len(ref_data)

    assert mse <= 0.0001, f"MSE is too high: {mse:.6f} > 0.0001. The cleaned data does not match the expected probabilistic output closely enough."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
