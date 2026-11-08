#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math

def test_results_json_exists():
    """Test that results.json was generated."""
    assert os.path.isfile("/home/user/results.json"), "The file /home/user/results.json does not exist. Did you run the script?"

def test_results_json_content():
    """Test that results.json contains the correct primer and covariance matrix."""
    with open("/home/user/results.json", "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "/home/user/results.json is not valid JSON."

    assert "primer" in data, "The 'primer' key is missing from results.json."
    assert "covariance" in data, "The 'covariance' key is missing from results.json."

    # Check primer
    expected_primer = "TCGATCGCAT"
    assert data["primer"] == expected_primer, f"Expected primer '{expected_primer}', but got '{data['primer']}'."

    # Check covariance
    cov = data["covariance"]
    assert isinstance(cov, list), "Covariance should be a list of lists."
    assert len(cov) == 2, f"Covariance matrix should have 2 rows, got {len(cov)}."
    for row in cov:
        assert isinstance(row, list), "Covariance should be a list of lists."
        assert len(row) == 2, f"Each row in covariance matrix should have 2 columns, got {len(row)}."

    expected_cov = [
        [2.3850550098908383, 0.02640243171887962],
        [0.02640243171887962, 2.4334346747572793]
    ]

    for i in range(2):
        for j in range(2):
            assert math.isclose(cov[i][j], expected_cov[i][j], rel_tol=1e-5, abs_tol=1e-5), \
                f"Covariance matrix value at ({i}, {j}) is incorrect. Expected {expected_cov[i][j]}, got {cov[i][j]}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
