#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
from pathlib import Path

import numpy as np
import pytest
from PIL import Image, ImageStat

HOME = Path('/home/user')
DATA = Path('/app/experimental_data.csv')
SOURCE = HOME / 'fit_model.cpp'
BINARY = HOME / 'fit_model'
COMPILED = Path('/tmp/fit_model_from_source')


def parse_pair(path):
    content = Path(path).read_text().strip()
    first, second = content.split(',')
    values = (float(first), float(second))
    assert all(math.isfinite(v) for v in values), f'Non-finite value in {path}: {content}'
    return values


def run_model(executable):
    means = HOME / 'posterior_means.txt'
    means.unlink(missing_ok=True)
    result = subprocess.run(
        [str(executable)], cwd=str(HOME), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert result.returncode == 0, (
        f'{executable} failed with exit code {result.returncode}. '
        f'stdout={result.stdout[-1000:]!r}, stderr={result.stderr[-1000:]!r}'
    )
    assert means.is_file(), f'{executable} did not create posterior_means.txt'
    return parse_pair(means)


@pytest.fixture(scope='session', autouse=True)
def exercise_submission():
    assert SOURCE.is_file(), 'Required source file /home/user/fit_model.cpp not found.'
    assert BINARY.is_file(), 'Required executable /home/user/fit_model not found.'
    assert os.access(BINARY, os.X_OK), '/home/user/fit_model is not executable.'

    source_text = SOURCE.read_text(errors='replace')
    assert len(source_text) >= 500, 'fit_model.cpp is implausibly small.'
    assert re.search(r'\b(for|while)\s*\(', source_text), 'No sampling loop found in fit_model.cpp.'
    assert re.search(r'(mt19937|default_random_engine|random_device|uniform_real_distribution|normal_distribution|\brand\s*\()', source_text), (
        'fit_model.cpp contains no random-number generation for MCMC/bootstrap.'
    )
    mh_terms = re.findall(r'(metropolis|proposal|accept|likelihood|log[_ ]?post|posterior)', source_text, re.I)
    assert len(mh_terms) >= 2, 'fit_model.cpp does not show evidence of a Metropolis-Hastings calculation.'

    build = subprocess.run(
        ['g++', '-std=c++11', '-O2', str(SOURCE), '-o', str(COMPILED)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert build.returncode == 0, f'fit_model.cpp does not compile: {build.stderr[-2000:]}'

    original_data = DATA.read_bytes()
    x = np.arange(0.0, 5.1, 0.1)
    test_alpha, test_beta = 3.4, 1.15
    noise = 0.045 * np.sin(4.7 * x) + 0.018 * np.cos(8.3 * x)
    y = test_alpha * x * np.exp(-test_beta * x) + noise
    synthetic = 'x,y\n' + ''.join(f'{xi:.4f},{yi:.8f}\n' for xi, yi in zip(x, y))

    try:
        DATA.write_text(synthetic)
        installed_est = run_model(BINARY)
        source_est = run_model(COMPILED)
    finally:
        DATA.write_bytes(original_data)

    installed_error = abs(installed_est[0] - test_alpha) + abs(installed_est[1] - test_beta)
    source_error = abs(source_est[0] - test_alpha) + abs(source_est[1] - test_beta)
    assert installed_error <= 0.45, (
        f'/home/user/fit_model did not adapt to a changed dataset: got {installed_est}, '
        f'expected approximately {(test_alpha, test_beta)}.'
    )
    assert source_error <= 0.45, (
        f'Executable compiled from fit_model.cpp did not fit a changed dataset: got {source_est}, '
        f'expected approximately {(test_alpha, test_beta)}.'
    )
    assert abs(installed_est[0] - 4.2) + abs(installed_est[1] - 1.5) >= 0.25, (
        'fit_model appears to emit the original parameters regardless of the input data.'
    )

    # Leave final artifacts produced by the submitted executable on the real dataset.
    run_model(BINARY)
    yield


def test_posterior_means_metric():
    target_file = '/home/user/posterior_means.txt'
    assert os.path.exists(target_file), f'Error: {target_file} not found.'

    with open(target_file, 'r') as f:
        content = f.read().strip()

    try:
        alpha_str, beta_str = content.split(',')
        alpha_est = float(alpha_str)
        beta_est = float(beta_str)
    except Exception as e:
        pytest.fail(f'Error parsing {target_file}: {e}. Expected format: alpha_mean,beta_mean')

    assert math.isfinite(alpha_est) and math.isfinite(beta_est), 'Posterior means must be finite.'
    true_alpha = 4.2
    true_beta = 1.5

    error = abs(alpha_est - true_alpha) + abs(beta_est - true_beta)
    threshold = 0.2

    assert error <= threshold, f'Estimated alpha={alpha_est}, beta={beta_est}. Error metric (Sum of Absolute Differences) is {error}, which is > {threshold}.'


def test_fit_model_binary_exists():
    binary_path = '/home/user/fit_model'
    assert os.path.exists(binary_path), f'Error: {binary_path} not found. Ensure fit_model.cpp is compiled.'
    assert os.path.isfile(binary_path), f'Error: {binary_path} is not a file.'
    assert os.access(binary_path, os.X_OK), f'Error: {binary_path} is not executable.'


def test_bootstrap_ci_exists_and_valid():
    ci_file = '/home/user/bootstrap_ci.txt'
    assert os.path.exists(ci_file), f'Error: {ci_file} not found.'

    with open(ci_file, 'r') as f:
        content = f.read().strip()

    try:
        lower_str, upper_str = content.split(',')
        lower_bound = float(lower_str)
        upper_bound = float(upper_str)
    except Exception as e:
        pytest.fail(f'Error parsing {ci_file}: {e}. Expected format: lower_bound,upper_bound')

    assert math.isfinite(lower_bound) and math.isfinite(upper_bound), 'Bootstrap bounds must be finite.'
    assert lower_bound <= upper_bound, f'Lower bound ({lower_bound}) is greater than upper bound ({upper_bound}).'
    assert lower_bound >= 0.0, 'An MSE confidence interval cannot have a negative lower bound.'
    assert upper_bound > lower_bound, 'Bootstrap MSE confidence interval must have nonzero width.'

    alpha_est, beta_est = parse_pair('/home/user/posterior_means.txt')
    data = np.genfromtxt('/app/experimental_data.csv', delimiter=',', names=True)
    predicted = alpha_est * data['x'] * np.exp(-beta_est * data['x'])
    squared_residuals = (data['y'] - predicted) ** 2
    observed_mse = float(np.mean(squared_residuals))
    assert lower_bound <= observed_mse <= upper_bound, (
        f'Bootstrap interval [{lower_bound}, {upper_bound}] does not contain the fitted MSE {observed_mse}.'
    )

    rng = np.random.default_rng(73129)
    draws = rng.choice(squared_residuals, size=(6000, len(squared_residuals)), replace=True).mean(axis=1)
    expected_lower, expected_upper = np.quantile(draws, [0.025, 0.975])
    lower_tol = max(0.004, 0.75 * float(expected_lower))
    upper_tol = max(0.004, 0.75 * float(expected_upper))
    assert abs(lower_bound - expected_lower) <= lower_tol, (
        f'Bootstrap lower bound {lower_bound} is inconsistent with residual resampling (about {expected_lower}).'
    )
    assert abs(upper_bound - expected_upper) <= upper_tol, (
        f'Bootstrap upper bound {upper_bound} is inconsistent with residual resampling (about {expected_upper}).'
    )


def test_fit_plot_exists():
    plot_file = '/home/user/fit_plot.png'
    assert os.path.exists(plot_file), f'Error: {plot_file} not found.'
    assert os.path.isfile(plot_file), f'Error: {plot_file} is not a file.'
    assert os.path.getsize(plot_file) > 0, f'Error: {plot_file} is empty.'

    with Image.open(plot_file) as image:
        assert image.format == 'PNG', 'fit_plot.png is not a valid PNG image.'
        image.verify()
    with Image.open(plot_file) as image:
        rgb = image.convert('RGB')
        width, height = rgb.size
        assert width >= 300 and height >= 200, f'Plot is too small: {width}x{height}.'
        extrema = ImageStat.Stat(rgb).extrema
        assert any(high - low >= 20 for low, high in extrema), 'Plot image is blank or nearly uniform.'
        colors = rgb.resize((min(width, 400), min(height, 300))).getcolors(maxcolors=200000)
        assert colors is None or len(colors) >= 20, 'Plot lacks enough visual content for data and a fitted curve.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
