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
    """Check that the virtual environment was created and contains a Python executable."""
    venv_python = "/home/user/venv/bin/python"
    assert os.path.isfile(venv_python), f"Virtual environment Python executable not found at {venv_python}."

def test_summary_json_exists_and_format():
    """Check that summary.json exists and has the correct key."""
    summary_file = "/home/user/summary.json"
    assert os.path.isfile(summary_file), f"Summary file {summary_file} missing."

    with open(summary_file, "r") as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("summary.json is not a valid JSON file.")

    assert "sum_top_5_singular_values" in summary, "Key 'sum_top_5_singular_values' missing in summary.json."
    assert isinstance(summary["sum_top_5_singular_values"], float), "The value for 'sum_top_5_singular_values' must be a float."

def test_pod_results_and_computations():
    """
    Use the student's virtual environment to verify the HDF5 results and the math.
    This avoids requiring third-party libraries in the pytest runner itself.
    """
    pod_results = "/home/user/pod_results.h5"
    assert os.path.isfile(pod_results), f"POD results file {pod_results} missing."

    verification_script = """
import sys
try:
    import numpy as np
    import h5py
    import json
except ImportError as e:
    print(f"Missing required package: {e}", file=sys.stderr)
    sys.exit(1)

# Ground truth computation
with h5py.File("/home/user/sim_data.h5", "r") as f:
    D = f["velocity_field"][:]

mean_D = np.mean(D, axis=0)
D_prime = D - mean_D
U, S, Vt = np.linalg.svd(D_prime, full_matrices=False)

top_5_s = S[:5]
top_5_vt = Vt[:5, :]
expected_sum = float(np.sum(top_5_s))

# Verify outputs
with h5py.File("/home/user/pod_results.h5", "r") as f:
    assert "singular_values" in f, "Dataset 'singular_values' missing in pod_results.h5"
    assert "top_modes" in f, "Dataset 'top_modes' missing in pod_results.h5"

    agent_s = f["singular_values"][:]
    agent_vt = f["top_modes"][:]

assert np.allclose(agent_s, top_5_s, atol=1e-5), "Singular values mismatch."
assert agent_vt.shape == (5, 1000), f"Modes shape mismatch. Expected (5, 1000), got {agent_vt.shape}."

# Singular vectors are unique up to an independent sign flip for each mode.
for i in range(5):
    same_sign = np.allclose(agent_vt[i], top_5_vt[i], atol=1e-5)
    opposite_sign = np.allclose(agent_vt[i], -top_5_vt[i], atol=1e-5)
    assert same_sign or opposite_sign, f"Spatial mode {i} does not match the corresponding POD mode."

with open("/home/user/summary.json", "r") as f:
    summary = json.load(f)

assert np.isclose(summary["sum_top_5_singular_values"], expected_sum, atol=1e-5), "Summary sum mismatch."
print("SUCCESS")
"""
    script_path = "/tmp/verify_pod.py"
    with open(script_path, "w") as f:
        f.write(verification_script)

    venv_python = "/home/user/venv/bin/python"
    result = subprocess.run([venv_python, script_path], capture_output=True, text=True)

    assert result.returncode == 0, f"Verification script failed with error:\n{result.stderr}\nStdout:\n{result.stdout}"
    assert "SUCCESS" in result.stdout, "Verification script did not complete successfully."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
