#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import subprocess
import pytest

def test_output_files_exist():
    """Test that the required output files have been generated."""
    assert os.path.exists('/home/user/viral_plot.png'), "The plot file /home/user/viral_plot.png is missing."
    assert os.path.exists('/home/user/viral_simulation.h5'), "The HDF5 file /home/user/viral_simulation.h5 is missing."

    # Check basic file magic number for HDF5 (starts with \x89HDF\r\n\x1a\n)
    with open('/home/user/viral_simulation.h5', 'rb') as f:
        magic = f.read(8)
        assert magic == b'\x89HDF\r\n\x1a\n', "The file /home/user/viral_simulation.h5 is not a valid HDF5 file."

def test_hdf5_data_content():
    """Test the contents of the HDF5 file by shelling out to a script that uses h5py and numpy."""
    # Since we are restricted to standard library, we use a subprocess to run the validation
    # using the packages the user was expected to install.
    verification_script = """
import sys
try:
    import h5py
    import numpy as np
except ImportError:
    # If the user didn't install them, they couldn't have completed the task properly,
    # but we exit with a specific code to distinguish from validation failures.
    sys.exit(2)

try:
    with h5py.File('/home/user/viral_simulation.h5', 'r') as f:
        expected_strains = ['Strain_Alpha', 'Strain_Beta', 'Strain_Gamma', 'Strain_Delta']
        for strain in expected_strains:
            if strain not in f:
                print(f"Dataset '{strain}' is missing from the HDF5 file.")
                sys.exit(1)

        alpha = f['Strain_Alpha'][:]
        beta = f['Strain_Beta'][:]
        gamma = f['Strain_Gamma'][:]
        delta = f['Strain_Delta'][:]

        if len(alpha) != 100 or len(beta) != 100 or len(gamma) != 100 or len(delta) != 100:
            print("Each dataset array length must be exactly 100.")
            sys.exit(1)

        # Strain_Beta has 0% GC content -> r = 0 -> V(t) remains 1.0
        if not np.allclose(beta, 1.0):
            print("Strain_Beta (GC=0) should have a constant viral load of V=1.0.")
            sys.exit(1)

        t = np.linspace(0, 50, 100)

        def analytical_solution(t, r, K=1000, V0=1.0):
            return K / (1 + ((K - V0) / V0) * np.exp(-r * t))

        # GC contents: Alpha=9/14, Gamma=14/14, Delta=4/8
        expected_alpha = analytical_solution(t, 0.5 * (9/14))
        expected_gamma = analytical_solution(t, 0.5 * 1.0)
        expected_delta = analytical_solution(t, 0.5 * (4/8))

        if not np.allclose(alpha, expected_alpha, atol=1e-2):
            print("Strain_Alpha values do not match the expected logistic growth curve.")
            sys.exit(1)
        if not np.allclose(gamma, expected_gamma, atol=1e-2):
            print("Strain_Gamma values do not match the expected logistic growth curve.")
            sys.exit(1)
        if not np.allclose(delta, expected_delta, atol=1e-2):
            print("Strain_Delta values do not match the expected logistic growth curve.")
            sys.exit(1)

except Exception as e:
    print(f"Error reading HDF5 file: {e}")
    sys.exit(1)

sys.exit(0)
"""
    result = subprocess.run([sys.executable, "-c", verification_script], capture_output=True, text=True)

    if result.returncode == 2:
        pytest.fail("Required packages (h5py, numpy) are not installed in the environment. The task could not be completed.")
    elif result.returncode != 0:
        pytest.fail(f"HDF5 data validation failed: {result.stdout.strip()}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
