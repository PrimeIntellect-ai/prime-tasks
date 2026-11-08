#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'EXERCISE_EOF' > /tmp/exercise_submission.py
import json
import os
import secrets
import subprocess
import sys

import h5py
import numpy as np

HOME = '/home/user'
DATA_FILE = '/home/user/data/profiles.h5'
RESULT_FILE = '/home/user/result.json'
MARKER_FILE = '/tmp/executed_script.txt'


def optimum(a, b, target):
    delta = a - b
    denominator = float(np.dot(delta, delta))
    if denominator == 0:
        raise RuntimeError('Reference profiles are identical.')
    value = float(np.dot(target - b, delta) / denominator)
    return min(1.0, max(0.0, value))


def read_alpha():
    with open(RESULT_FILE, 'r') as f:
        data = json.load(f)
    if not isinstance(data, dict) or set(data) != {'alpha'}:
        raise ValueError('result.json must contain exactly the alpha key')
    value = data['alpha']
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError('alpha must be numeric')
    return float(value)


def run_script(path):
    if os.path.exists(RESULT_FILE):
        os.remove(RESULT_FILE)
    completed = subprocess.run(
        [sys.executable, path],
        cwd=os.path.dirname(path) or HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    if completed.returncode != 0 or not os.path.isfile(RESULT_FILE):
        return None
    try:
        return read_alpha()
    except Exception:
        return None


def write_profiles(a, b, target):
    with h5py.File(DATA_FILE, 'w') as f:
        f.create_dataset('reference_A', data=a)
        f.create_dataset('reference_B', data=b)
        f.create_dataset('target_sample', data=target)


def main():
    if not os.path.isfile(DATA_FILE):
        raise RuntimeError(f'{DATA_FILE} does not exist')

    candidates = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d != '__pycache__' and not d.startswith('.')]
        for name in files:
            path = os.path.join(root, name)
            if name.endswith('.py') and os.path.isfile(path):
                candidates.append(path)
    candidates.sort()
    if not candidates:
        raise RuntimeError('No Python script was found under /home/user')

    with open(DATA_FILE, 'rb') as f:
        original_h5 = f.read()

    with h5py.File(DATA_FILE, 'r') as f:
        original_a = np.asarray(f['reference_A'][:], dtype=float)
        original_b = np.asarray(f['reference_B'][:], dtype=float)
        original_target = np.asarray(f['target_sample'][:], dtype=float)
    original_expected = round(optimum(original_a, original_b, original_target), 4)

    rng = np.random.default_rng(secrets.randbits(128))
    n = len(original_a)
    challenge_a = rng.random(n)
    challenge_b = rng.random(n)
    challenge_alpha = rng.uniform(0.20, 0.40)
    challenge_target = (
        challenge_alpha * challenge_a
        + (1.0 - challenge_alpha) * challenge_b
        + rng.normal(0.0, 0.003, n)
    )
    challenge_expected = round(
        optimum(challenge_a, challenge_b, challenge_target), 4
    )

    selected = None
    try:
        for script in candidates:
            with open(DATA_FILE, 'wb') as f:
                f.write(original_h5)
            write_profiles(challenge_a, challenge_b, challenge_target)
            challenge_value = run_script(script)
            if challenge_value is None or abs(challenge_value - challenge_expected) > 0.0001:
                continue

            with open(DATA_FILE, 'wb') as f:
                f.write(original_h5)
            original_value = run_script(script)
            if original_value is None or abs(original_value - original_expected) > 0.0001:
                continue

            selected = script
            break
    finally:
        with open(DATA_FILE, 'wb') as f:
            f.write(original_h5)

    if selected is None:
        raise RuntimeError(
            'No submitted Python script computed the least-squares alpha for both the provided and verification datasets.'
        )

    with open(MARKER_FILE, 'w') as f:
        f.write(selected)


if __name__ == '__main__':
    main()
EXERCISE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest
import h5py
import numpy as np

RESULT_FILE = '/home/user/result.json'
MARKER_FILE = '/tmp/executed_script.txt'
DATA_FILE = '/home/user/data/profiles.h5'

def test_requested_script_was_executed():
    """Check that a submitted Python script was found and successfully exercised."""
    assert os.path.isfile(MARKER_FILE), "No submitted Python script was successfully executed."
    with open(MARKER_FILE, 'r') as f:
        script = f.read().strip()
    assert script.endswith('.py') and os.path.isfile(script), "The exercised artifact is not a Python script."

def test_result_file_exists():
    """Check if the result.json file exists."""
    assert os.path.isfile(RESULT_FILE), f"{RESULT_FILE} does not exist."

def test_result_format():
    """Check if result.json is valid JSON and contains the required key."""
    with open(RESULT_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULT_FILE} does not contain valid JSON.")

    assert isinstance(data, dict), f"JSON in {RESULT_FILE} should be an object/dictionary."
    assert 'alpha' in data, f"'alpha' key is missing from {RESULT_FILE}."
    assert isinstance(data['alpha'], (int, float)), "'alpha' value should be a number."

def test_alpha_matches_profiles_file():
    """Independently recompute the bounded least-squares optimum from the HDF5 data."""
    with h5py.File(DATA_FILE, 'r') as f:
        reference_a = np.asarray(f['reference_A'][:], dtype=float)
        reference_b = np.asarray(f['reference_B'][:], dtype=float)
        target = np.asarray(f['target_sample'][:], dtype=float)

    delta = reference_a - reference_b
    expected = np.dot(target - reference_b, delta) / np.dot(delta, delta)
    expected = round(float(np.clip(expected, 0.0, 1.0)), 4)

    with open(RESULT_FILE, 'r') as f:
        agent_alpha = json.load(f)['alpha']
    assert abs(agent_alpha - expected) <= 0.0001, (
        f"The alpha does not match the least-squares optimum from {DATA_FILE}. "
        f"Expected {expected}, got {agent_alpha}."
    )

def test_alpha_value():
    """Check if the calculated alpha value is correct."""
    with open(RESULT_FILE, 'r') as f:
        data = json.load(f)

    agent_alpha = data.get('alpha')
    # The expected alpha is computed from the deterministic setup using np.random.seed(42)
    # expected_alpha = 0.6508
    expected_alpha = 0.6508

    assert abs(agent_alpha - expected_alpha) <= 0.0001, (
        f"The calculated alpha value is incorrect. Expected {expected_alpha}, got {agent_alpha}."
    )
TEST_EOF

if python3 /tmp/exercise_submission.py 2>&1 && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
