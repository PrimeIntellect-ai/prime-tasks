#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import math
import pytest

def test_results_json_exists():
    assert os.path.isfile('/home/user/results.json'), "The file /home/user/results.json does not exist."

def test_results_values():
    # Recompute C_obs_1 and C_obs_2 from spectra.csv using trapezoidal rule
    spectra_path = '/home/user/spectra.csv'
    assert os.path.isfile(spectra_path), "The file /home/user/spectra.csv is missing."

    wavelengths = []
    int1 = []
    int2 = []

    with open(spectra_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            wavelengths.append(float(row['Wavelength']))
            int1.append(float(row['Intensity_1']))
            int2.append(float(row['Intensity_2']))

    # Trapezoidal rule
    def trapz(x, y):
        area = 0.0
        for i in range(1, len(x)):
            area += (x[i] - x[i-1]) * (y[i] + y[i-1]) / 2.0
        return area

    c_obs_1_expected = trapz(wavelengths, int1)
    c_obs_2_expected = trapz(wavelengths, int2)

    # Check results.json
    with open('/home/user/results.json', 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file /home/user/results.json is not valid JSON.")

    assert "C_obs_1" in results, "Key 'C_obs_1' missing in results.json"
    assert "C_obs_2" in results, "Key 'C_obs_2' missing in results.json"
    assert "k" in results, "Key 'k' missing in results.json"

    assert math.isclose(results["C_obs_1"], round(c_obs_1_expected, 4), abs_tol=1e-4), \
        f"Expected C_obs_1 to be {round(c_obs_1_expected, 4)}, got {results['C_obs_1']}"

    assert math.isclose(results["C_obs_2"], round(c_obs_2_expected, 4), abs_tol=1e-4), \
        f"Expected C_obs_2 to be {round(c_obs_2_expected, 4)}, got {results['C_obs_2']}"

    # Expected k is 0.5000 based on the mass balance equations
    assert math.isclose(results["k"], 0.5000, abs_tol=1e-3), \
        f"Expected k to be approximately 0.5000, got {results['k']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
