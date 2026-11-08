#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import math
import os
import secrets
import stat
import subprocess

import matplotlib.image as mpimg
import numpy as np

PROJECT = '/home/user/project'
SCRIPT = os.path.join(PROJECT, 'clean_and_analyze.py')
DATA = os.path.join(PROJECT, 'data.csv')
RESULTS = os.path.join(PROJECT, 'results.json')
PLOT = os.path.join(PROJECT, 'posterior.png')


def compute_expected_results(data_path=DATA):
    values = []
    num_nans = 0
    with open(data_path, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames is not None and 'value' in reader.fieldnames
        for row in reader:
            text = row['value'].strip()
            if text.lower() == 'nan':
                num_nans += 1
            else:
                values.append(float(text))

    values_np = np.asarray(values, dtype=float)
    q1, q3 = np.percentile(values_np, [25, 75])
    iqr = q3 - q1
    cleaned = values_np[
        (values_np >= q1 - 1.5 * iqr) & (values_np <= q3 + 1.5 * iqr)
    ]
    assert len(cleaned) > 0

    imputed = np.random.RandomState(42).choice(
        cleaned, size=num_nans, replace=True
    )
    final_dataset = np.concatenate((cleaned, imputed))
    n = len(final_dataset)
    total = float(final_dataset.sum())

    best_alpha = None
    min_mse = float('inf')
    for alpha in [1.0, 5.0, 10.0]:
        errors = []
        for x_i in final_dataset:
            mu_pred = (total - float(x_i)) / (1.0 / alpha**2 + n - 1)
            errors.append((float(x_i) - mu_pred) ** 2)
        mse = sum(errors) / n
        if mse < min_mse:
            min_mse = mse
            best_alpha = alpha

    posterior_variance = 1.0 / (1.0 / best_alpha**2 + n)
    posterior_mean = posterior_variance * total
    return {
        'best_alpha': round(best_alpha, 4),
        'posterior_mean': round(posterior_mean, 4),
        'posterior_variance': round(posterior_variance, 4),
    }


def run_submission():
    for path in (RESULTS, PLOT):
        if os.path.lexists(path):
            os.remove(path)
    env = os.environ.copy()
    env['MPLBACKEND'] = 'Agg'
    completed = subprocess.run(
        ['python3', SCRIPT],
        cwd=PROJECT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert completed.returncode == 0, (
        'clean_and_analyze.py failed:\n'
        + completed.stdout
        + '\n'
        + completed.stderr
    )


def assert_outputs(expected):
    # Preserve the original result-file assertions.
    assert os.path.exists(RESULTS), f'{RESULTS} does not exist.'
    with open(RESULTS) as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError('results.json is not a valid JSON file.') from exc

    assert 'best_alpha' in results, "Missing 'best_alpha' in results.json"
    assert 'posterior_mean' in results, "Missing 'posterior_mean' in results.json"
    assert 'posterior_variance' in results, "Missing 'posterior_variance' in results.json"
    for key in ('best_alpha', 'posterior_mean', 'posterior_variance'):
        assert isinstance(results[key], (int, float)) and not isinstance(results[key], bool)
        assert math.isfinite(float(results[key]))
        assert math.isclose(
            float(results[key]), expected[key], rel_tol=1e-3, abs_tol=1e-4
        ), f"Expected {key} ~ {expected[key]}, got {results[key]}"

    # Preserve the original PNG assertions, then verify it decodes and is rendered.
    assert os.path.exists(PLOT), f'{PLOT} does not exist.'
    assert os.path.getsize(PLOT) > 0, f'{PLOT} is an empty file.'
    with open(PLOT, 'rb') as f:
        header = f.read(8)
    assert header == b'\x89PNG\r\n\x1a\n', f'{PLOT} is not a valid PNG file.'

    try:
        image = mpimg.imread(PLOT)
    except Exception as exc:
        raise AssertionError('posterior.png is not a decodable PNG image') from exc
    assert image.ndim in (2, 3)
    assert image.shape[0] >= 50 and image.shape[1] >= 50, 'posterior.png is too small'
    rgb = image[..., :3] if image.ndim == 3 else image
    assert np.isfinite(rgb).all(), 'posterior.png contains invalid pixels'
    assert float(np.ptp(rgb)) > 0.02, 'posterior.png appears blank'

    with open(PLOT, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def write_dataset(rows):
    with open(DATA, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['value'])
        for value in rows:
            writer.writerow([value])


def test_script_executes_and_handles_unseen_inputs():
    assert os.path.exists(SCRIPT), f'{SCRIPT} does not exist.'
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f'{SCRIPT} is not a regular file.'
    assert os.path.getsize(SCRIPT) > 0, f'{SCRIPT} is empty.'

    with open(DATA, 'rb') as f:
        original_data = f.read()

    plot_hashes = []
    try:
        # Execute against the pre-populated dataset and retain all original checks.
        expected = compute_expected_results()
        run_submission()
        plot_hashes.append(assert_outputs(expected))

        # Exercise the submitted script on unpredictable datasets rather than trusting
        # artifacts created before verification.
        rng = secrets.SystemRandom()
        centers = [rng.uniform(-9.0, -4.0), rng.uniform(3.0, 8.0), rng.uniform(12.0, 20.0)]
        nan_counts = [1, 3, 2]
        for index, (center, nan_count) in enumerate(zip(centers, nan_counts)):
            offsets = [-1.4, -0.9, -0.55, -0.2, 0.0, 0.15, 0.35, 0.65, 0.95, 1.25, 0.45, -0.35]
            scale = rng.uniform(0.45, 1.35)
            rows = [round(center + scale * x, 6) for x in offsets]
            rows += [round(center - 1000 - index * 37, 6), round(center + 1200 + index * 41, 6)]
            for _ in range(nan_count):
                rows.insert(rng.randrange(len(rows) + 1), 'NaN')
            write_dataset(rows)
            expected = compute_expected_results()
            run_submission()
            plot_hashes.append(assert_outputs(expected))

        assert len(set(plot_hashes)) == len(plot_hashes), (
            'posterior.png did not change across datasets with different posteriors'
        )
    finally:
        with open(DATA, 'wb') as f:
            f.write(original_data)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
