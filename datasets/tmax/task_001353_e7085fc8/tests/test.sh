#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import json

def test_marginal_file_exists():
    """Test that the output HDF5 file exists."""
    output_file = "/home/user/marginal_xy.h5"
    assert os.path.exists(output_file), f"Output file {output_file} is missing."
    assert os.path.isfile(output_file), f"Path {output_file} is not a file."

def test_marginal_values_and_shape():
    """Test that the marginal distribution is computed correctly."""
    # We use a subprocess to evaluate the HDF5 file using numpy/h5py/scipy
    # since the test file itself must only import standard library modules.
    script = """
import h5py
import numpy as np
from scipy.interpolate import interp1d
import sys
import json

try:
    with h5py.File('/home/user/input_pdf.h5', 'r') as f:
        density = f['density'][:]

    z_old = np.linspace(0, 1, 50)
    z_new = np.linspace(0, 1, 99)

    f_interp = interp1d(z_old, density, axis=2, kind='linear')
    density_refined = f_interp(z_new)

    expected_marginal = np.trapz(density_refined, x=z_new, axis=2)

    with h5py.File('/home/user/marginal_xy.h5', 'r') as f:
        if 'marginal' not in f:
            print(json.dumps({"error": "Dataset 'marginal' not found in output file."}))
            sys.exit(1)
        actual_marginal = f['marginal'][:]

    if actual_marginal.shape != (50, 50):
        print(json.dumps({"error": f"Shape mismatch: expected (50, 50), got {actual_marginal.shape}"}))
        sys.exit(1)

    max_diff = float(np.max(np.abs(expected_marginal - actual_marginal)))
    if max_diff > 1e-5:
        print(json.dumps({"error": f"Values do not match expected. Max difference: {max_diff}"}))
        sys.exit(1)

    print(json.dumps({"success": True}))
    sys.exit(0)
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(1)
"""
    result = subprocess.run(['python3', '-c', script], capture_output=True, text=True)

    try:
        output = json.loads(result.stdout)
    except json.JSONDecodeError:
        assert False, f"Failed to parse verification script output.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    assert result.returncode == 0, f"Verification failed: {output.get('error', 'Unknown error')}"
    assert output.get("success") is True, output.get("error")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
