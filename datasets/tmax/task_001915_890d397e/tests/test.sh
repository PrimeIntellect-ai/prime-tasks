#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import shutil
import subprocess

import pytest

VENV = '/home/user/venv'
PYTHON = os.path.join(VENV, 'bin', 'python')
SCRIPT = '/home/user/analyze.py'
DATA = '/home/user/data/conversions.csv'
METRICS = '/home/user/artifacts/metrics.json'
PLOT = '/home/user/artifacts/posterior.png'


def test_virtual_environment_exists():
    assert os.path.isdir(VENV), f"Virtual environment directory {VENV} does not exist."
    assert os.path.isfile(PYTHON) or os.path.isfile(os.path.join(VENV, 'Scripts', 'python.exe')), \
        "Python executable not found in the virtual environment."


def test_required_packages_installed():
    python_bin = PYTHON
    if not os.path.exists(python_bin):
        python_bin = os.path.join(VENV, 'Scripts', 'python.exe')
    assert os.path.exists(python_bin), "Cannot find venv python executable to check packages."

    for pkg in ['numpy', 'scipy', 'matplotlib', 'pandas']:
        result = subprocess.run([python_bin, '-c', f'import {pkg}'], capture_output=True)
        assert result.returncode == 0, \
            f"Package '{pkg}' is not installed in the virtual environment or fails to import."


def csv_counts(path):
    successes = 0
    trials = 0
    with open(path, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames is not None
        assert 'id' in reader.fieldnames and 'clicked' in reader.fieldnames
        for row in reader:
            value = int(row['clicked'])
            assert value in (0, 1), f"Invalid clicked value: {value}"
            successes += value
            trials += 1
    return successes, trials


def expected_values(path):
    successes, trials = csv_counts(path)
    alpha = 1 + successes
    beta = 1 + trials - successes
    mean = alpha / (alpha + beta)
    variance = (alpha * beta) / (((alpha + beta) ** 2) * (alpha + beta + 1))
    return alpha, beta, mean, variance


def check_metrics(path, expected):
    assert os.path.isfile(path), f"Metrics file {path} does not exist."
    try:
        with open(path) as f:
            metrics = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{path} is not a valid JSON file.")

    expected_keys = {'posterior_alpha', 'posterior_beta', 'posterior_mean', 'posterior_variance'}
    assert set(metrics.keys()) == expected_keys, \
        f"Metrics JSON must contain exactly keys {expected_keys}. Found: {list(metrics.keys())}"

    assert isinstance(metrics['posterior_alpha'], int), "posterior_alpha must be an integer."
    assert isinstance(metrics['posterior_beta'], int), "posterior_beta must be an integer."
    assert isinstance(metrics['posterior_mean'], float), "posterior_mean must be a float."
    assert isinstance(metrics['posterior_variance'], float), "posterior_variance must be a float."

    alpha, beta, mean, variance = expected
    assert metrics['posterior_alpha'] == alpha, \
        f"Expected posterior_alpha={alpha}, got {metrics['posterior_alpha']}"
    assert metrics['posterior_beta'] == beta, \
        f"Expected posterior_beta={beta}, got {metrics['posterior_beta']}"
    assert math.isclose(metrics['posterior_mean'], mean, rel_tol=1e-5), \
        f"Expected posterior_mean ~ {mean}, got {metrics['posterior_mean']}"
    assert math.isclose(metrics['posterior_variance'], variance, rel_tol=1e-5), \
        f"Expected posterior_variance ~ {variance}, got {metrics['posterior_variance']}"


def check_png_file(path):
    assert os.path.isfile(path), f"Plot file {path} does not exist."
    size = os.path.getsize(path)
    assert size > 2000, \
        f"Plot file {path} is too small ({size} bytes). It is likely empty or blank."
    with open(path, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', f"File {path} is not a valid PNG image."


def write_probe(successes, failures):
    with open(DATA, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['id', 'clicked'])
        values = [1] * successes + [0] * failures
        for i, value in enumerate(values):
            writer.writerow([i, value])


def run_analysis():
    assert os.path.isfile(SCRIPT), f"Analysis script {SCRIPT} does not exist."
    for path in (METRICS, PLOT):
        if os.path.lexists(path):
            os.remove(path)
    result = subprocess.run(
        [PYTHON, SCRIPT], cwd='/home/user', capture_output=True, text=True, timeout=180
    )
    assert result.returncode == 0, \
        f"analyze.py failed with exit code {result.returncode}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"


def validate_decoded_plots(low_path, high_path, final_path):
    validator = r'''
import sys
import matplotlib.image as mpimg
import numpy as np


def rgb(path):
    image = np.asarray(mpimg.imread(path), dtype=float)
    assert image.ndim == 3 and image.shape[0] >= 100 and image.shape[1] >= 100
    assert np.isfinite(image).all()
    if image.shape[2] == 4:
        image = image[:, :, :3] * image[:, :, 3:4] + (1.0 - image[:, :, 3:4])
    else:
        image = image[:, :, :3]
    if image.max() > 1.5:
        image = image / 255.0
    assert image.std() > 0.01, 'decoded PNG is blank or nearly uniform'
    assert np.mean(np.min(image, axis=2) < 0.95) > 0.001, 'decoded PNG contains no visible plot content'
    return image

low = rgb(sys.argv[1])
high = rgb(sys.argv[2])
rgb(sys.argv[3])
assert low.shape == high.shape, 'probe plots unexpectedly changed canvas dimensions'

# The probe posteriors are mirror images, concentrated near 0.2 and 0.8.
# Comparing decoded luminance removes common axes and labels and verifies that
# the plotted content moves from the left to the right with the posterior.
low_dark = 1.0 - low.mean(axis=2)
high_dark = 1.0 - high.mean(axis=2)
delta = low_dark - high_dark
left_content = np.maximum(delta, 0.0)
right_content = np.maximum(-delta, 0.0)
assert left_content.sum() / delta.size > 1e-5, 'plots do not visibly respond to changed posterior data'
assert right_content.sum() / delta.size > 1e-5, 'plots do not visibly respond to changed posterior data'
x = np.arange(delta.shape[1], dtype=float) / max(1, delta.shape[1] - 1)
left_x = (left_content.sum(axis=0) * x).sum() / left_content.sum()
right_x = (right_content.sum(axis=0) * x).sum() / right_content.sum()
assert left_x < 0.48, f'low-rate posterior content is not on the left side of the plot: {left_x}'
assert right_x > 0.52, f'high-rate posterior content is not on the right side of the plot: {right_x}'
'''
    result = subprocess.run(
        [PYTHON, '-c', validator, low_path, high_path, final_path],
        capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, \
        f"Posterior PNG validation failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"


def test_analysis_pipeline_uses_csv_and_generates_posterior_plot():
    with open(DATA, 'rb') as f:
        original_data = f.read()

    low_plot = '/tmp/posterior_low.png'
    high_plot = '/tmp/posterior_high.png'
    try:
        write_probe(20, 80)
        low_expected = expected_values(DATA)
        run_analysis()
        check_metrics(METRICS, low_expected)
        check_png_file(PLOT)
        shutil.copyfile(PLOT, low_plot)

        write_probe(80, 20)
        high_expected = expected_values(DATA)
        run_analysis()
        check_metrics(METRICS, high_expected)
        check_png_file(PLOT)
        shutil.copyfile(PLOT, high_plot)
    finally:
        with open(DATA, 'wb') as f:
            f.write(original_data)

    # Re-run against the real supplied CSV so the required final artifacts are
    # left in their correct final state.
    final_expected = expected_values(DATA)
    run_analysis()
    check_metrics(METRICS, final_expected)
    check_png_file(PLOT)
    validate_decoded_plots(low_plot, high_plot, PLOT)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
