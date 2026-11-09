#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import pytest

def test_resonance_results():
    results_path = '/home/user/resonance_results.json'

    # Check if the output file exists
    assert os.path.isfile(results_path), f"Output file not found at {results_path}"

    # Load the JSON data
    with open(results_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} is not a valid JSON.")

    # Check required keys
    required_keys = {'f1', 'f2', 'f3', 'total_energy_integral'}
    missing_keys = required_keys - set(data.keys())
    assert not missing_keys, f"Missing keys in JSON output: {missing_keys}"

    # Extract values
    try:
        f1 = float(data['f1'])
        f2 = float(data['f2'])
        f3 = float(data['f3'])
        agent_energy = float(data['total_energy_integral'])
    except ValueError:
        pytest.fail("One or more values in the JSON cannot be converted to float.")

    # Check that frequencies are sorted
    assert f1 < f2 < f3, f"Frequencies must be sorted: f1={f1}, f2={f2}, f3={f3}"

    # Check that frequencies are somewhat close to the expected modes (440, 880, 1500)
    # Give a wide tolerance since we are mostly grading the energy integral
    assert 300 < f1 < 600, f"f1={f1} is far from the expected first mode (~440 Hz)"
    assert 700 < f2 < 1000, f"f2={f2} is far from the expected second mode (~880 Hz)"
    assert 1300 < f3 < 1700, f"f3={f3} is far from the expected third mode (~1500 Hz)"

    # Metric threshold validation
    # Ground truth reference value based on deterministic audio generation and specified welch parameters
    target_energy = 394745.8

    # Calculate absolute relative error
    relative_error = abs(agent_energy - target_energy) / target_energy

    # Tolerance/Threshold: <= 0.05 (Agent's relative error must be 5% or less)
    threshold = 0.05

    assert relative_error <= threshold, (
        f"Relative error of total_energy_integral is too high. "
        f"Agent energy: {agent_energy}, Target energy: {target_energy}, "
        f"Relative error: {relative_error:.4f}, Threshold: {threshold}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
