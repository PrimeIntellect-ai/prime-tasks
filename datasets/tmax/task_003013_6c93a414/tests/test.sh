#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import numpy as np
import scipy.stats as stats


def compute_truth():
    fs = 1024
    t = np.arange(1024) / fs
    power = 3.0 * np.sin(2 * np.pi * 50 * t) + 2.0 * np.cos(2 * np.pi * 120 * t)
    np.random.seed(42)
    power += np.random.normal(0, 0.5, 1024)

    fft_vals = np.fft.fft(power)
    fft_freqs = np.fft.fftfreq(1024, 1 / fs)
    pos_mask = fft_freqs > 0
    pos_freqs = fft_freqs[pos_mask]
    pos_mags = np.abs(fft_vals)[pos_mask]
    sorted_indices = np.argsort(pos_mags)[::-1]
    dom_freqs = [pos_freqs[sorted_indices[0]], pos_freqs[sorted_indices[1]]]

    np.random.seed(42)
    latencies = np.random.lognormal(mean=3.0, sigma=0.5, size=5000)
    p99 = np.percentile(latencies, 99)
    kde = stats.gaussian_kde(latencies)
    grid = np.linspace(0, 200, 2000)
    kde_peak = grid[np.argmax(kde(grid))]

    convergence_n = -1
    for n in range(2, 5001):
        sem = np.std(latencies[:n], ddof=1) / np.sqrt(n)
        if sem < 0.20:
            convergence_n = n
            break

    return {
        "dominant_frequencies": [round(float(dom_freqs[0]), 2), round(float(dom_freqs[1]), 2)],
        "latency_kde_peak": round(float(kde_peak), 2),
        "latency_p99": round(float(p99), 2),
        "convergence_n": convergence_n,
    }


def test_profiling_report():
    report_path = '/home/user/profiling_report.json'
    assert os.path.isfile(report_path), f"The output file {report_path} was not found."

    with open(report_path, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {report_path} does not contain valid JSON."

    truth_data = compute_truth()

    expected_keys = ["dominant_frequencies", "latency_kde_peak", "latency_p99", "convergence_n"]
    for key in expected_keys:
        assert key in report_data, f"The key '{key}' is missing from the profiling report."

    rep_freqs = report_data["dominant_frequencies"]
    truth_freqs = truth_data["dominant_frequencies"]
    assert isinstance(rep_freqs, list) and len(rep_freqs) == 2, "dominant_frequencies must be a list of two elements."
    assert rep_freqs == truth_freqs, f"Expected dominant_frequencies to be {truth_freqs}, but got {rep_freqs}."

    rep_peak = report_data["latency_kde_peak"]
    truth_peak = truth_data["latency_kde_peak"]
    assert isinstance(rep_peak, (int, float)), "latency_kde_peak must be a number."
    assert abs(rep_peak - truth_peak) <= 0.05, f"Expected latency_kde_peak to be approximately {truth_peak}, but got {rep_peak}."

    rep_p99 = report_data["latency_p99"]
    truth_p99 = truth_data["latency_p99"]
    assert isinstance(rep_p99, (int, float)), "latency_p99 must be a number."
    assert abs(rep_p99 - truth_p99) <= 0.05, f"Expected latency_p99 to be approximately {truth_p99}, but got {rep_p99}."

    rep_n = report_data["convergence_n"]
    truth_n = truth_data["convergence_n"]
    assert isinstance(rep_n, int), "convergence_n must be an integer."
    assert rep_n == truth_n, f"Expected convergence_n to be {truth_n}, but got {rep_n}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
