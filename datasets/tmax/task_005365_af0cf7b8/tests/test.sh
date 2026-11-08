#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

EXPECTED_BASELINE = (
    b"10Hz\t0.10\n"
    b"20Hz\t0.20\n"
    b"30Hz\t0.40\n"
    b"40Hz\t0.20\n"
    b"50Hz\t0.10\n"
)

EXPECTED_CANDIDATES = {
    "machine_A.txt": (
        b"10Hz\t0.15\n"
        b"20Hz\t0.20\n"
        b"30Hz\t0.30\n"
        b"40Hz\t0.20\n"
        b"50Hz\t0.15\n"
    ),
    "machine_B.txt": (
        b"10Hz\t0.00\n"
        b"20Hz\t0.10\n"
        b"30Hz\t0.80\n"
        b"40Hz\t0.10\n"
        b"50Hz\t0.00\n"
    ),
    "machine_C.txt": (
        b"10Hz\t0.10\n"
        b"20Hz\t0.25\n"
        b"30Hz\t0.30\n"
        b"40Hz\t0.25\n"
        b"50Hz\t0.10\n"
    ),
    "machine_D.txt": (
        b"10Hz\t0.20\n"
        b"20Hz\t0.20\n"
        b"30Hz\t0.20\n"
        b"40Hz\t0.20\n"
        b"50Hz\t0.20\n"
    ),
}

def read_spectrum(filepath):
    """Reads a spectrum file and returns a dictionary of frequency -> probability."""
    spectrum = {}
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) == 2:
                freq, prob = parts[0], float(parts[1])
                spectrum[freq] = prob
    return spectrum

def calculate_tvd(p, q):
    """Calculates the Total Variation Distance between two probability distributions."""
    tvd = 0.0
    all_keys = set(p.keys()).union(set(q.keys()))
    for k in all_keys:
        p_val = p.get(k, 0.0)
        q_val = q.get(k, 0.0)
        tvd += abs(p_val - q_val)
    return tvd / 2.0

def test_accepted_machines_log_correctness():
    baseline_path = "/home/user/baseline_spectrum.txt"
    candidates_dir = "/home/user/candidates"
    output_log_path = "/home/user/accepted_machines.log"

    assert os.path.exists(baseline_path), f"Baseline file missing at {baseline_path}"
    assert os.path.exists(candidates_dir), f"Candidates directory missing at {candidates_dir}"
    assert os.path.exists(output_log_path), f"Output log file missing at {output_log_path}"

    assert os.path.isfile(baseline_path), f"Baseline path is not a file: {baseline_path}"
    assert os.path.isdir(candidates_dir), f"Candidates path is not a directory: {candidates_dir}"

    with open(baseline_path, 'rb') as f:
        assert f.read() == EXPECTED_BASELINE, "Baseline fixture was modified"

    actual_candidate_names = sorted(
        name for name in os.listdir(candidates_dir) if name.endswith('.txt')
    )
    assert actual_candidate_names == sorted(EXPECTED_CANDIDATES), (
        "Candidate fixture set was deleted, renamed, or modified by adding files.\n"
        f"Expected: {sorted(EXPECTED_CANDIDATES)}\n"
        f"Found: {actual_candidate_names}"
    )

    for filename, expected_contents in EXPECTED_CANDIDATES.items():
        candidate_path = os.path.join(candidates_dir, filename)
        assert os.path.isfile(candidate_path), f"Candidate fixture is not a file: {candidate_path}"
        with open(candidate_path, 'rb') as f:
            assert f.read() == expected_contents, f"Candidate fixture was modified: {filename}"

    baseline_spectrum = read_spectrum(baseline_path)
    expected_accepted = []

    for filename in os.listdir(candidates_dir):
        if not filename.endswith('.txt'):
            continue

        candidate_path = os.path.join(candidates_dir, filename)
        candidate_spectrum = read_spectrum(candidate_path)
        tvd = calculate_tvd(baseline_spectrum, candidate_spectrum)

        if tvd <= 0.15:
            machine_name = filename[:-4]
            expected_accepted.append(machine_name)

    expected_accepted.sort()

    with open(output_log_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_accepted, (
        f"The contents of {output_log_path} do not match the expected accepted machines.\n"
        f"Expected: {expected_accepted}\n"
        f"Found: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
