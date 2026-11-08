#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import stat
import pytest
import numpy as np

def test_simulator_executable_exists():
    path = "/home/user/simulator"
    assert os.path.isfile(path), f"Executable {path} is missing."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."

def test_observations_csv_exists():
    path = "/home/user/observations.csv"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "seqA,42.1,44.5,43.2,41.8,45.0" in content, f"File {path} does not contain the expected CSV data for seqA."
    assert "seqB,25.4,26.1,24.8,25.9,27.0" in content, f"File {path} does not contain the expected CSV data for seqB."
    assert "seqC,50.1,48.5,49.2,51.0,49.8" in content, f"File {path} does not contain the expected CSV data for seqC."

def test_probabilities_json_exists_and_correct():
    path = "/home/user/probabilities.json"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")

    observations = {
        "seqA": [42.1, 44.5, 43.2, 41.8, 45.0],
        "seqB": [25.4, 26.1, 24.8, 25.9, 27.0],
        "seqC": [50.1, 48.5, 49.2, 51.0, 49.8],
    }
    expected_data = {}
    np.random.seed(42)
    for seq in sorted(observations):
        values = np.asarray(observations[seq], dtype=float)
        samples = np.random.normal(
            np.mean(values), np.std(values, ddof=1), 100_000
        )
        expected_data[seq] = round(float(np.mean(samples > 45.0)), 4)

    for seq, expected_prob in expected_data.items():
        assert seq in data, f"Sequence {seq} is missing from the JSON output."
        assert isinstance(data[seq], (int, float)), f"Value for {seq} is not a number."
        assert round(data[seq], 4) == expected_prob, f"Probability for {seq} is incorrect. Expected {expected_prob}, got {data[seq]}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
