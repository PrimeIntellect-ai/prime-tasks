#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import urllib.request
import urllib.error
import pytest

def test_fit_results_file():
    """Check if /home/user/fit_results.csv exists, has correct headers, and accurate fit parameters."""
    filepath = "/home/user/fit_results.csv"
    assert os.path.isfile(filepath), f"File {filepath} does not exist."

    expected_params = {
        "seq_alpha": {"A": 2.5, "omega": 3.0, "phi": 1.0, "C": 0.5},
        "seq_beta": {"A": 1.2, "omega": 1.5, "phi": -0.5, "C": -0.2},
        "seq_gamma": {"A": 4.0, "omega": 5.0, "phi": 2.0, "C": 1.0},
    }

    parsed_results = {}
    with open(filepath, "r") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["seq_id", "A", "omega", "phi", "C"], f"CSV header is incorrect. Got {reader.fieldnames}"
        for row in reader:
            seq_id = row["seq_id"]
            parsed_results[seq_id] = {
                "A": float(row["A"]),
                "omega": float(row["omega"]),
                "phi": float(row["phi"]),
                "C": float(row["C"]),
            }

    for seq_id, expected in expected_params.items():
        assert seq_id in parsed_results, f"Missing sequence {seq_id} in fit_results.csv."
        res = parsed_results[seq_id]

        # Check constraints
        assert res["A"] > 0, f"Amplitude A must be > 0 for {seq_id}, got {res['A']}."
        assert -math.pi <= res["phi"] <= math.pi, f"Phase phi must be in [-pi, pi] for {seq_id}, got {res['phi']}."

        # Check values with tolerance
        tol = 0.05
        assert math.isclose(res["A"], expected["A"], abs_tol=tol), f"A for {seq_id} is {res['A']}, expected ~{expected['A']}."
        assert math.isclose(res["omega"], expected["omega"], abs_tol=tol), f"omega for {seq_id} is {res['omega']}, expected ~{expected['omega']}."
        assert math.isclose(res["C"], expected["C"], abs_tol=tol), f"C for {seq_id} is {res['C']}, expected ~{expected['C']}."
        assert math.isclose(res["phi"], expected["phi"], abs_tol=tol), f"phi for {seq_id} is {res['phi']}, expected ~{expected['phi']}."

    # Check that the decoy sequence was not included
    assert "seq_decoy" not in parsed_results, "Decoy sequence 'seq_decoy' should not be in fit_results.csv."

def test_http_server():
    """Check if the background HTTP server is running on port 8080 and serving the file correctly."""
    url = "http://localhost:8080/fit_results.csv"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            content = response.read().decode("utf-8")
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to fetch {url}. Is the HTTP server running? Error: {e}")

    # Verify that the fetched content matches the file on disk
    filepath = "/home/user/fit_results.csv"
    assert os.path.isfile(filepath), f"File {filepath} does not exist."
    with open(filepath, "r") as f:
        file_content = f.read()

    assert content.strip() == file_content.strip(), "Content served by HTTP server does not match the local fit_results.csv file."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
