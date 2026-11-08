#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math

def compute_dft_bin(signal, k):
    N = len(signal)
    real = 0.0
    imag = 0.0
    for n, x in enumerate(signal):
        angle = -2 * math.pi * k * n / N
        real += x * math.cos(angle)
        imag += x * math.sin(angle)
    return real**2 + imag**2

def calc_energy(seq):
    mapping = {'A': 1.0, 'C': -1.0, 'G': 0.5, 'T': -0.5}
    signal = [mapping.get(c, 0.0) for c in seq.strip()]
    if not signal:
        return 0.0

    k_start = 360
    k_end = 420

    P = {}
    for k in range(k_start, k_end + 1):
        P[k] = compute_dft_bin(signal, k)

    energy = 0.0
    for k in range(k_start + 1, k_end + 1):
        energy += (P[k-1] + P[k]) / 2.0 * (1.0 / 1200.0)
    return energy

def get_expected_results():
    ref_file = '/home/user/data/reference.txt'
    sample_file = '/home/user/data/sample.txt'

    with open(ref_file, 'r') as f:
        ref_seqs = [line.strip() for line in f if line.strip()]

    with open(sample_file, 'r') as f:
        sample_seq = f.read().strip()

    ref_energies = [calc_energy(s) for s in ref_seqs]
    ref_mean = sum(ref_energies) / len(ref_energies)

    variance = sum((x - ref_mean)**2 for x in ref_energies) / (len(ref_energies) - 1)
    ref_std = math.sqrt(variance)

    sample_energy = calc_energy(sample_seq)
    z_score = (sample_energy - ref_mean) / ref_std

    return {
        "reference_mean": ref_mean,
        "reference_std": ref_std,
        "sample_energy": sample_energy,
        "z_score": z_score
    }

def test_spectrum_plot_exists():
    plot_path = "/home/user/output/spectrum.png"
    assert os.path.isfile(plot_path), f"The plot file {plot_path} does not exist."
    assert os.path.getsize(plot_path) > 0, f"The plot file {plot_path} is empty."

def test_results_json():
    results_path = "/home/user/output/results.json"
    assert os.path.isfile(results_path), f"The results file {results_path} does not exist."

    with open(results_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {results_path} does not contain valid JSON."

    expected = get_expected_results()

    keys = ["reference_mean", "reference_std", "sample_energy", "z_score"]
    for key in keys:
        assert key in results, f"Key '{key}' is missing from {results_path}."
        assert isinstance(results[key], (int, float)), f"Value for '{key}' must be a float."

        actual_val = results[key]
        expected_val = expected[key]
        assert math.isclose(actual_val, expected_val, rel_tol=1e-2, abs_tol=1e-2), \
            f"Value for '{key}' is incorrect. Expected ~{expected_val:.4f}, got {actual_val:.4f}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
