#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import math
import subprocess
import json
import pytest

def get_real_root(x, y, z):
    """Compute the single real root using Cardano's formula."""
    p = y - x**2 / 3.0
    q = z - x*y / 3.0 + 2.0 * x**3 / 27.0
    delta = (q / 2.0)**2 + (p / 3.0)**3

    # Based on the problem description, there is exactly 1 real root, so delta > 0
    if delta >= 0:
        sqrt_delta = math.sqrt(delta)
        u3 = -q / 2.0 + sqrt_delta
        v3 = -q / 2.0 - sqrt_delta
        u = math.copysign(math.pow(abs(u3), 1.0/3.0), u3)
        v = math.copysign(math.pow(abs(v3), 1.0/3.0), v3)
        t = u + v
    else:
        # Fallback for 3 real roots (should not happen based on generation)
        theta = math.acos(-q / 2.0 / math.sqrt(-(p / 3.0)**3))
        t = 2.0 * math.sqrt(-p / 3.0) * math.cos(theta / 3.0)

    return t - x / 3.0

@pytest.fixture(scope="module")
def expected_data():
    w_list = []
    csv_path = '/home/user/raw_data.csv'
    assert os.path.exists(csv_path), f"Missing {csv_path}"

    with open(csv_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            x, y, z = float(row['x']), float(row['y']), float(row['z'])
            w = get_real_root(x, y, z)
            w_list.append(w)

    expected_w_sum = math.fsum(w_list)
    return w_list, expected_w_sum

def test_virtual_environment_exists():
    assert os.path.exists('/home/user/venv/bin/python'), "Virtual environment Python executable not found at /home/user/venv/bin/python"

def test_w_sum_log_content(expected_data):
    _, expected_w_sum = expected_data
    log_path = '/home/user/w_sum.log'
    assert os.path.exists(log_path), f"Log file missing at {log_path}"

    with open(log_path, 'r') as f:
        content = f.read().strip()

    assert len(content) > 0, "Log file is empty"

    # Check format: exactly 10 decimal places
    parts = content.split('.')
    assert len(parts) == 2, "Log file content does not contain a decimal point"
    assert len(parts[1]) == 10, f"Expected exactly 10 decimal places, found {len(parts[1])}"

    logged_sum = float(content)
    assert math.isclose(logged_sum, expected_w_sum, rel_tol=1e-7, abs_tol=1e-7), \
        f"Logged sum {logged_sum} does not match expected sum {expected_w_sum} within tolerance"

def test_hdf5_output(expected_data):
    w_list, expected_w_sum = expected_data
    h5_path = '/home/user/processed_data.h5'
    assert os.path.exists(h5_path), f"HDF5 file missing at {h5_path}"

    # We use the user's venv to read the HDF5 file since third-party libs are not allowed in the test environment
    script = f"""
import sys
import json
try:
    import h5py
except ImportError:
    print(json.dumps({{"error": "h5py not installed in venv"}}))
    sys.exit(0)

try:
    with h5py.File('{h5_path}', 'r') as f:
        w_sum = f.attrs.get('w_sum')
        w_values = list(f['w_values'][:])
        print(json.dumps({{"w_sum": float(w_sum) if w_sum is not None else None, "w_values": w_values}}))
except Exception as e:
    print(json.dumps({{"error": str(e)}}))
"""

    result = subprocess.run(['/home/user/venv/bin/python', '-c', script], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to run verification script in user venv"

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Failed to parse output from HDF5 reader script: {result.stdout}")

    if "error" in data:
        pytest.fail(f"Error reading HDF5 file: {data['error']}")

    assert data.get("w_sum") is not None, "Attribute 'w_sum' not found in HDF5 root group"
    assert math.isclose(data["w_sum"], expected_w_sum, rel_tol=1e-7, abs_tol=1e-7), \
        f"HDF5 w_sum attribute {data['w_sum']} does not match expected {expected_w_sum}"

    w_values = data.get("w_values")
    assert w_values is not None, "Dataset 'w_values' not found in HDF5 file"
    assert len(w_values) == len(w_list), f"Expected {len(w_list)} values in HDF5, got {len(w_values)}"

    # Check that individual values match closely
    for i, (actual, expected) in enumerate(zip(w_values, w_list)):
        assert math.isclose(actual, expected, rel_tol=1e-5, abs_tol=1e-5), \
            f"Value mismatch at index {i}: actual {actual}, expected {expected}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
