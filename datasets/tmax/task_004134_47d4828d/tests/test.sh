#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import pytest

def test_venv_exists():
    """Check that the virtual environment was created and contains python."""
    python_path = "/home/user/venv/bin/python"
    assert os.path.exists(python_path), f"Virtual environment Python executable not found at {python_path}."

def test_packages_installed():
    """Check that numpy and scikit-learn are installed in the virtual environment."""
    python_path = "/home/user/venv/bin/python"
    result = subprocess.run(
        [python_path, "-c", "import numpy; import sklearn"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Failed to import numpy or sklearn in the virtual environment. Error: {result.stderr}"

def test_json_output_exists_and_valid():
    """Check that nn_stability.json exists and contains correct values."""
    json_path = "/home/user/nn_stability.json"
    assert os.path.exists(json_path), f"Output file {json_path} is missing."

    with open(json_path, 'r') as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    assert isinstance(actual, dict), "JSON root should be a dictionary."
    assert len(actual) == 100, f"Expected 100 entries in JSON, got {len(actual)}."

    # Verify the exact values using a script run within the student's venv (which has numpy)
    verify_script = """
import numpy as np
import json
import sys

try:
    X = np.loadtxt('/home/user/data/vectors.csv', delimiter=',')
except Exception as e:
    print("Failed to load vectors.csv")
    sys.exit(2)

np.random.seed(42)

def cosine_sim(a, b):
    # a is 1D, b is 2D
    num = np.dot(b, a)
    den = np.linalg.norm(b, axis=1) * np.linalg.norm(a)
    # Avoid division by zero
    den[den == 0] = 1e-10
    return num / den

expected = {}
for i in range(100):
    a = X[i]
    b_indices = [j for j in range(100) if j != i]
    b = X[b_indices]

    sims = cosine_sim(a, b)
    best_idx_in_b = np.argmax(sims)
    original_nn = b_indices[best_idx_in_b]

    matches = 0
    for _ in range(100):
        cols = np.random.choice(10, size=10, replace=True)
        a_boot = a[cols]
        b_boot = b[:, cols]

        sims_boot = cosine_sim(a_boot, b_boot)
        best_idx_in_b_boot = np.argmax(sims_boot)
        boot_nn = b_indices[best_idx_in_b_boot]

        if boot_nn == original_nn:
            matches += 1

    expected[str(i)] = matches / 100.0

with open('/home/user/nn_stability.json', 'r') as f:
    actual = json.load(f)

for k, v in expected.items():
    actual_val = actual.get(k)
    if actual_val is None:
        print(f"Missing key {k} in JSON")
        sys.exit(1)
    if abs(float(actual_val) - v) > 1e-4:
        print(f"Mismatch at index {k}: expected {v}, got {actual_val}")
        sys.exit(1)

print("Success")
sys.exit(0)
"""
    script_path = "/tmp/verify_nn_stability.py"
    with open(script_path, "w") as f:
        f.write(verify_script)

    python_path = "/home/user/venv/bin/python"
    result = subprocess.run([python_path, script_path], capture_output=True, text=True)

    if result.returncode == 2:
        pytest.fail(f"Verification script failed to load data: {result.stdout}")
    elif result.returncode != 0:
        pytest.fail(f"Data verification failed. {result.stdout.strip()}\n{result.stderr.strip()}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
