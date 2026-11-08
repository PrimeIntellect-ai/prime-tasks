#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import math
import pytest

def compute_expected_results():
    eiip_path = "/home/user/eiip.tsv"
    fasta_path = "/home/user/proteins.fasta"

    assert os.path.isfile(eiip_path), f"Required file {eiip_path} is missing."
    assert os.path.isfile(fasta_path), f"Required file {fasta_path} is missing."

    # Parse EIIP values
    eiip = {}
    with open(eiip_path, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                parts = line.split()
                if len(parts) >= 2:
                    eiip[parts[0]] = float(parts[1])

    # Parse FASTA sequences
    seqs = {}
    current_id = None
    with open(fasta_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith(">"):
                current_id = line
                seqs[current_id] = []
            elif current_id is not None:
                seqs[current_id].extend(list(line))

    # Compute DFT and find peak
    expected_results = {}
    for seq_id, seq_list in seqs.items():
        signal = [eiip.get(aa, 0.0) for aa in seq_list]

        # Truncate or pad to 256
        if len(signal) > 256:
            signal = signal[:256]
        else:
            signal = signal + [0.0] * (256 - len(signal))

        max_power = -1.0
        peak_idx = -1
        N = 256

        # Calculate DFT power for indices 1 to 127
        for k in range(1, 128):
            real = sum(signal[n] * math.cos(-2 * math.pi * k * n / N) for n in range(N))
            imag = sum(signal[n] * math.sin(-2 * math.pi * k * n / N) for n in range(N))
            power = real**2 + imag**2

            if power > max_power:
                max_power = power
                peak_idx = k

        expected_results[seq_id] = peak_idx

    return expected_results

def test_script_exists_and_executable():
    script_path = "/home/user/analyze_rrm.sh"
    assert os.path.isfile(script_path), f"The script {script_path} was not found."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable. Run 'chmod +x {script_path}'."

def test_results_correctness():
    results_path = "/home/user/results.txt"
    assert os.path.isfile(results_path), f"The output file {results_path} was not found."

    expected = compute_expected_results()

    actual = {}
    with open(results_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            assert ":" in line, f"Line in {results_path} is incorrectly formatted (missing colon): {line}"
            seq_id, val = line.split(":", 1)
            try:
                actual[seq_id.strip()] = int(val.strip())
            except ValueError:
                pytest.fail(f"Could not parse peak index as integer in line: {line}")

    for seq_id, expected_peak in expected.items():
        assert seq_id in actual, f"Sequence {seq_id} is missing from {results_path}."
        assert actual[seq_id] == expected_peak, f"Incorrect peak index for {seq_id}. Expected {expected_peak}, got {actual[seq_id]}."

    # Check for extra unexpected sequences
    for seq_id in actual:
        assert seq_id in expected, f"Found unexpected sequence ID in results: {seq_id}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
