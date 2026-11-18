#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import sys

import numpy as np
import pytest


def test_script_exists():
    """Test that the analysis script was created."""
    script_path = "/home/user/analyze_sequence.py"
    assert os.path.isfile(script_path), f"Script not found: {script_path}"


def test_results_json_exists_and_valid():
    """Execute the script and verify all reported values against NumPy."""
    script_path = "/home/user/analyze_sequence.py"
    results_path = "/home/user/results.json"
    fasta_path = "/home/user/sequence.fasta"

    assert os.path.isfile(script_path), f"Script not found: {script_path}"
    assert os.path.isfile(fasta_path), f"File not found: {fasta_path}"

    with open(fasta_path, "rb") as f:
        fasta_before = f.read()

    if os.path.lexists(results_path):
        os.unlink(results_path)

    completed = subprocess.run(
        [sys.executable, script_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert completed.returncode == 0, (
        f"analyze_sequence.py failed with exit code {completed.returncode}\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )

    assert os.path.isfile(results_path), f"File not found: {results_path}"

    with open(fasta_path, "rb") as f:
        assert f.read() == fasta_before, "analyze_sequence.py must not modify sequence.fasta"

    with open(results_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} is not valid JSON.")

    expected_keys = {"max_diff", "peak_index", "peak_magnitude"}
    assert set(results.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}"

    assert isinstance(results["peak_index"], int), "peak_index must be an integer"
    assert isinstance(results["max_diff"], float), "max_diff must be a float"
    assert isinstance(results["peak_magnitude"], float), "peak_magnitude must be a float"

    with open(fasta_path, "r") as f:
        lines = f.readlines()

    seq = "".join(l.strip() for l in lines if not l.startswith(">"))
    N = len(seq)
    assert N > 0, "Sequence is empty"

    eiip = {'A': 0.1260, 'C': 0.1340, 'G': 0.0806, 'T': 0.1335}
    values = [eiip[char] for char in seq]
    array32 = np.array(values, dtype=np.float32)
    array64 = np.array(values, dtype=np.float64)
    magnitude32 = np.abs(np.fft.fft(array32))
    magnitude64 = np.abs(np.fft.fft(array64))

    search = magnitude64[1:N // 2 + 1]
    expected_peak_index = int(np.argmax(search)) + 1
    expected_peak_magnitude = float(magnitude64[expected_peak_index])
    expected_max_diff = float(np.max(np.abs(magnitude32 - magnitude64)))

    assert results["peak_index"] == expected_peak_index, (
        f"Expected peak_index to be {expected_peak_index}, got {results['peak_index']}"
    )

    assert math.isclose(
        results["peak_magnitude"], expected_peak_magnitude,
        rel_tol=1e-9, abs_tol=1e-9
    ), (
        f"Expected peak_magnitude approx {expected_peak_magnitude}, "
        f"got {results['peak_magnitude']}"
    )

    # Independently retain the original direct-DFT magnitude check at the selected peak.
    real = 0.0
    imag = 0.0
    peak_k = results["peak_index"]
    for n, char in enumerate(seq):
        val = eiip[char]
        angle = -2 * math.pi * peak_k * n / N
        real += val * math.cos(angle)
        imag += val * math.sin(angle)
    direct_expected_mag = math.hypot(real, imag)

    assert math.isclose(results["peak_magnitude"], direct_expected_mag, rel_tol=1e-3), (
        f"Expected peak_magnitude approx {direct_expected_mag}, "
        f"got {results['peak_magnitude']}"
    )

    assert math.isclose(
        results["max_diff"], expected_max_diff,
        rel_tol=1e-9, abs_tol=1e-12
    ), f"Expected max_diff approx {expected_max_diff}, got {results['max_diff']}"

    assert results["max_diff"] > 0.0, "max_diff should be greater than 0.0"
    assert results["max_diff"] < 1.0, "max_diff is unexpectedly large"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
