#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import pytest
from scipy import stats


def get_expected_values():
    pdb_path = "/home/user/structure.pdb"
    if not os.path.exists(pdb_path):
        pytest.fail(f"Required input file {pdb_path} is missing.")

    cas = []
    cbs = []

    with open(pdb_path, 'r') as f:
        for line in f:
            if line.startswith("ATOM"):
                name = line[12:16].strip()
                try:
                    bfac = float(line[60:66])
                except ValueError:
                    continue
                if name == 'CA':
                    cas.append(bfac)
                elif name == 'CB':
                    cbs.append(bfac)

    if not cas:
        pytest.fail("No CA atoms found in the PDB file.")
    if not cbs:
        pytest.fail("No CB atoms found in the PDB file.")

    ca_mean = math.fsum(cas) / len(cas)
    expected_ca_mean_str = f"{ca_mean:.6f}"

    result = stats.ttest_ind(cas, cbs, equal_var=False, alternative='two-sided')
    if not math.isfinite(float(result.pvalue)):
        pytest.fail("Welch's t-test did not produce a finite p-value.")
    expected_p_val_str = f"{float(result.pvalue):.6f}"

    return expected_ca_mean_str, expected_p_val_str


def test_ca_mean_file():
    """Test that ca_mean.txt exists and contains the correct exact arithmetic mean."""
    expected_ca_mean, _ = get_expected_values()

    ca_mean_path = "/home/user/ca_mean.txt"
    assert os.path.exists(ca_mean_path), f"File {ca_mean_path} was not created."

    with open(ca_mean_path, 'r') as f:
        content = f.read().strip()

    assert content == expected_ca_mean, f"Expected {ca_mean_path} to contain '{expected_ca_mean}', but got '{content}'."


def test_p_value_file():
    """Test that p_value.txt exists and contains the correct Welch t-test p-value."""
    _, expected_p_val = get_expected_values()

    p_val_path = "/home/user/p_value.txt"
    assert os.path.exists(p_val_path), f"File {p_val_path} was not created."

    with open(p_val_path, 'r') as f:
        content = f.read().strip()

    assert content == expected_p_val, f"Expected {p_val_path} to contain '{expected_p_val}', but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
