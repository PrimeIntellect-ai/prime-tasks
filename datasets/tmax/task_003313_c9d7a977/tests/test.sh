#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import pytest

def test_virtual_environment_exists():
    """Test that the virtual environment is created at the correct location."""
    venv_python = "/home/user/venv/bin/python"
    assert os.path.exists(venv_python), f"Virtual environment python not found at {venv_python}"

def test_results_json_exists():
    """Test that results.json exists."""
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), f"Missing file: {results_path}"
    assert os.path.isfile(results_path), f"Path is not a file: {results_path}"

def test_results_values():
    """Test that the values in results.json match the expected ground truth."""
    venv_python = "/home/user/venv/bin/python"
    assert os.path.exists(venv_python), "Cannot verify results without the virtual environment python."

    # Script to compute the ground truth using the student's environment
    truth_script = """
import numpy as np
from scipy import stats, optimize, integrate
import json

data = np.loadtxt('/home/user/events.csv')
kde = stats.gaussian_kde(data)

# mode
res = optimize.minimize_scalar(lambda x: -kde.pdf(x), bounds=(0, 10), method='bounded')
mode = float(res.x)

# integral
integral, _ = integrate.quad(kde.pdf, mode - 1.0, mode + 1.0)

# normal fit
mu, std = stats.norm.fit(data)

# wasserstein
rng_norm = np.random.default_rng(42)
norm_samples = rng_norm.normal(mu, std, 10000)
w_dist = stats.wasserstein_distance(data, norm_samples)

truth = {
    "mode": round(mode, 4),
    "integral": round(float(integral), 4),
    "wasserstein_distance": round(float(w_dist), 4)
}

print(json.dumps(truth))
"""

    try:
        result = subprocess.run(
            [venv_python, "-c", truth_script],
            capture_output=True,
            text=True,
            check=True
        )
        truth_data = json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to compute ground truth using the student's venv. Ensure numpy and scipy are installed. Error: {e.stderr}")
    except json.JSONDecodeError:
        pytest.fail("Failed to parse the ground truth output.")

    results_path = "/home/user/results.json"
    with open(results_path, 'r') as f:
        try:
            student_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} does not contain valid JSON.")

    expected_keys = ["mode", "integral", "wasserstein_distance"]
    for key in expected_keys:
        assert key in student_data, f"Missing key '{key}' in results.json"

        student_val = student_data[key]
        truth_val = truth_data[key]

        assert isinstance(student_val, (int, float)), f"Value for '{key}' must be a number."

        diff = abs(student_val - truth_val)
        assert diff <= 0.0002, f"Value for '{key}' is {student_val}, expected {truth_val} (diff {diff} exceeds tolerance 0.0002)"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
