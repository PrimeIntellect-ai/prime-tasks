#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

import numpy as np
import pandas as pd
import pytest

SCRIPT_PATH = '/home/user/mcmc_fit.py'
DATA_PATH = '/home/user/observational_data.csv'
RESULTS_PATH = '/home/user/results.txt'


def reference_result(t, y):
    fft_values = np.fft.fft(y)
    frequencies = np.fft.fftfreq(len(y), d=t[1] - t[0])
    dominant_index = np.argmax(np.abs(fft_values[1:len(y) // 2])) + 1

    current_a = 1.0
    current_f = float(frequencies[dominant_index])

    def log_likelihood(a, f):
        model = a * np.sin(2 * np.pi * f * t)
        residual = y - model
        return float(np.sum(-0.5 * (residual / 0.5) ** 2 - np.log(0.5 * np.sqrt(2 * np.pi))))

    current_ll = log_likelihood(current_a, current_f)
    samples = np.empty((20000, 2), dtype=float)

    np.random.seed(42)
    for i in range(20000):
        proposed_a = np.random.normal(current_a, 0.05)
        proposed_f = np.random.normal(current_f, 0.05)

        if 0 <= proposed_a <= 10 and 0 <= proposed_f <= 10:
            proposed_ll = log_likelihood(proposed_a, proposed_f)
            if np.log(np.random.rand()) < proposed_ll - current_ll:
                current_a = proposed_a
                current_f = proposed_f
                current_ll = proposed_ll

        samples[i] = (current_a, current_f)

    means = samples[5000:].mean(axis=0)
    return f'{means[0]:.2f},{means[1]:.2f}'


def run_submission():
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    completed = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert completed.returncode == 0, (
        f'mcmc_fit.py exited with status {completed.returncode}. '
        f'stdout: {completed.stdout}\nstderr: {completed.stderr}'
    )
    assert os.path.isfile(RESULTS_PATH), 'Running mcmc_fit.py did not create results.txt'

    with open(RESULTS_PATH, 'r') as f:
        content = f.read().strip()
    assert re.fullmatch(r'\d+\.\d{2},\d+\.\d{2}', content), (
        f"Expected exactly two decimal places in 'A_mean,f_mean' format, got '{content}'"
    )
    return content


def test_mcmc_fit_script_exists():
    """Test that the python script was created."""
    script_path = '/home/user/mcmc_fit.py'
    assert os.path.isfile(script_path), f"Expected script not found at {script_path}"


def test_script_executes_the_required_deterministic_sampler():
    """Exercise the submitted program on unpredictable data and compare to the specified MH chain."""
    original_data = open(DATA_PATH, 'rb').read()
    rng = np.random.default_rng(secrets.randbits(128))

    try:
        for _ in range(2):
            t = np.linspace(0, 5, 200)
            # Choose an exact positive FFT bin so initialization is unambiguous.
            bin_number = int(rng.integers(9, 36))
            f_true = bin_number / (len(t) * (t[1] - t[0]))
            a_true = float(rng.uniform(1.8, 3.5))
            y = a_true * np.sin(2 * np.pi * f_true * t) + rng.normal(0, 0.5, len(t))
            pd.DataFrame({'t': t, 'y': y}).to_csv(DATA_PATH, index=False)

            expected = reference_result(t, y)
            actual = run_submission()
            assert actual == expected, (
                f'Submitted sampler produced {actual}, but the required seeded '
                f'20000-iteration sampler produced {expected}'
            )
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_data)
        # Execute once more against the task's real observational data.
        run_submission()


def test_results_file_exists_and_correct():
    """Test that the results.txt file exists and contains correct values."""
    results_path = '/home/user/results.txt'
    assert os.path.isfile(results_path), f"Results file not found at {results_path}"

    with open(results_path, 'r') as f:
        content = f.read().strip()

    assert content, "The results.txt file is empty."

    parts = content.split(',')
    assert len(parts) == 2, f"Expected format 'A_mean,f_mean', but got '{content}'"

    try:
        a_mean = float(parts[0])
        f_mean = float(parts[1])
    except ValueError:
        pytest.fail(f"Could not parse floats from results.txt content: '{content}'")

    assert 2.34 <= a_mean <= 2.44, f"A_mean {a_mean} is outside the acceptable range [2.34, 2.44]"
    assert 3.65 <= f_mean <= 3.75, f"f_mean {f_mean} is outside the acceptable range [3.65, 3.75]"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
