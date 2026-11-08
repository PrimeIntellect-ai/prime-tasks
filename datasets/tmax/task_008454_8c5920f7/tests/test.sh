#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import json
import math

import numpy as np
from PIL import Image
from scipy.optimize import curve_fit


def _candidate_color_masks(rgb, background):
    """Yield masks for common rendered colors, including antialiased colors."""
    quantized = rgb // 16
    colors, counts = np.unique(quantized.reshape(-1, 3), axis=0, return_counts=True)
    order = np.argsort(counts)[::-1]
    yielded = 0
    for index in order:
        color = colors[index]
        count = int(counts[index])
        if count < 40:
            break
        rendered_color = color.astype(float) * 16.0 + 7.5
        if np.linalg.norm(rendered_color - background) < 25:
            continue
        yield np.all(quantized == color, axis=2)
        yielded += 1
        if yielded >= 80:
            break


def _longest_vertical_run(column):
    positions = np.flatnonzero(column)
    if positions.size == 0:
        return None
    split_at = np.flatnonzero(np.diff(positions) > 1) + 1
    groups = np.split(positions, split_at)
    group = max(groups, key=len)
    return int(group[0]), int(group[-1]), len(group)


def _has_histogram(rgb, background):
    """Detect multiple density-bar plateaus with a common baseline."""
    height, width, _ = rgb.shape
    for mask in _candidate_color_masks(rgb, background):
        tops = []
        bottoms = []
        xs = []
        for x in range(width):
            run = _longest_vertical_run(mask[:, x])
            if run is not None and run[2] >= max(5, int(height * 0.015)):
                top, bottom, _ = run
                xs.append(x)
                tops.append(top)
                bottoms.append(bottom)

        if len(xs) < width * 0.12:
            continue

        xs = np.asarray(xs, dtype=float)
        tops = np.asarray(tops, dtype=float)
        bottoms = np.asarray(bottoms, dtype=float)
        baseline = np.median(bottoms)
        aligned = np.abs(bottoms - baseline) <= 3
        if aligned.sum() < max(20, int(len(xs) * 0.55)):
            continue

        bar_x = xs[aligned]
        bar_tops = tops[aligned]
        if np.ptp(bar_tops) < height * 0.08:
            continue

        # Filled histogram bars have several distinct flat top levels. The
        # detector data are exponential, so their overall bar heights should
        # decrease as inter-arrival time increases (image y therefore rises).
        plateau_levels = np.unique(np.round(bar_tops / 3.0).astype(int))
        if plateau_levels.size < 5:
            continue
        if np.std(bar_x) == 0 or np.std(bar_tops) == 0:
            continue
        correlation = np.corrcoef(bar_x, bar_tops)[0, 1]
        if np.isfinite(correlation) and correlation > 0.20:
            return True
    return False


def _has_exponential_curve(rgb, background):
    """Find a thin, long rendered curve whose shape fits an exponential PDF."""
    height, width, _ = rgb.shape

    def model(x, offset, amplitude, decay):
        return offset + amplitude * np.exp(-decay * (x - x.min()))

    for mask in _candidate_color_masks(rgb, background):
        columns = []
        ys = []
        for x in range(width):
            positions = np.flatnonzero(mask[:, x])
            # A plotted line is thin; filled bars and vertical axes are not.
            if 1 <= positions.size <= 12:
                columns.append(x)
                ys.append(float(np.median(positions)))

        if len(columns) < width * 0.15:
            continue

        columns = np.asarray(columns, dtype=float)
        ys = np.asarray(ys, dtype=float)
        gaps = np.flatnonzero(np.diff(columns) > 7) + 1
        column_groups = np.split(columns, gaps)
        y_groups = np.split(ys, gaps)

        for x_group, y_group in zip(column_groups, y_groups):
            if x_group.size < width * 0.15 or np.ptp(x_group) < width * 0.25:
                continue
            if np.ptp(y_group) < height * 0.05:
                continue
            try:
                params, _ = curve_fit(
                    model,
                    x_group,
                    y_group,
                    p0=(float(np.max(y_group)), -float(np.ptp(y_group)), 0.01),
                    bounds=([-height, -2 * height, 1e-5],
                            [2 * height, -2.0, 0.2]),
                    maxfev=20000,
                )
            except (RuntimeError, ValueError, FloatingPointError):
                continue

            predicted = model(x_group, *params)
            residual = float(np.sum((y_group - predicted) ** 2))
            total = float(np.sum((y_group - np.mean(y_group)) ** 2))
            if total > 0 and 1.0 - residual / total >= 0.85:
                return True
    return False


def _validate_plot_contents(plot_path):
    # Pillow fully decodes the file, preventing a magic-number-only fake.
    with Image.open(plot_path) as image:
        image.verify()
    with Image.open(plot_path) as image:
        image = image.convert('RGB')
        rgb = np.asarray(image)

    assert rgb.shape[0] >= 300 and rgb.shape[1] >= 300, \
        "Plot resolution is too small to contain the required visualization."

    corner_pixels = np.concatenate((
        rgb[:10, :10].reshape(-1, 3),
        rgb[:10, -10:].reshape(-1, 3),
        rgb[-10:, :10].reshape(-1, 3),
        rgb[-10:, -10:].reshape(-1, 3),
    )).astype(float)
    background = np.median(corner_pixels, axis=0)
    distance = np.linalg.norm(rgb.astype(float) - background, axis=2)
    assert np.count_nonzero(distance > 25) > rgb.shape[0] * rgb.shape[1] * 0.01, \
        "Plot does not contain enough rendered chart content."

    assert _has_histogram(rgb, background), \
        "Plot does not contain a density histogram consistent with the inter-arrival data."
    assert _has_exponential_curve(rgb, background), \
        "Plot does not contain a visible fitted exponential PDF curve."


def test_fit_results_and_plot():
    csv_path = '/home/user/detector_events.csv'
    json_path = '/home/user/fit_results.json'
    plot_path = '/home/user/fit_plot.png'

    # 1. Verify CSV exists and compute expected values using standard library
    assert os.path.exists(csv_path), f"Input file {csv_path} is missing."

    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        timestamps = [float(row['timestamp']) for row in reader]

    assert len(timestamps) > 1, "Not enough timestamps to compute intervals."

    diffs = [timestamps[i] - timestamps[i-1] for i in range(1, len(timestamps))]

    # Compute lambda (1 / mean)
    mean_diff = sum(diffs) / len(diffs)
    expected_lambda = 1.0 / mean_diff

    # Compute KS statistic manually
    diffs.sort()
    n = len(diffs)
    expected_ks = 0.0
    for i, x in enumerate(diffs):
        # Theoretical CDF for exponential distribution
        cdf_x = 1.0 - math.exp(-expected_lambda * x)

        # Empirical CDF jumps at x
        ecdf_prev = i / n
        ecdf_next = (i + 1) / n

        # KS stat is the maximum distance
        ks_prev = abs(ecdf_prev - cdf_x)
        ks_next = abs(ecdf_next - cdf_x)
        expected_ks = max(expected_ks, ks_prev, ks_next)

    # 2. Verify JSON results
    assert os.path.exists(json_path), f"Results file {json_path} is missing."

    with open(json_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} is not a valid JSON file."

    assert 'lambda' in results, "'lambda' key missing from JSON."
    assert 'ks_stat' in results, "'ks_stat' key missing from JSON."

    actual_lambda = results['lambda']
    actual_ks = results['ks_stat']

    expected_lambda_rounded = round(expected_lambda, 4)
    expected_ks_rounded = round(expected_ks, 4)

    assert abs(actual_lambda - expected_lambda_rounded) <= 1e-4, \
        f"Expected lambda to be approximately {expected_lambda_rounded}, but got {actual_lambda}"

    assert abs(actual_ks - expected_ks_rounded) <= 1e-4, \
        f"Expected ks_stat to be approximately {expected_ks_rounded}, but got {actual_ks}"

    # 3. Verify Plot
    assert os.path.exists(plot_path), f"Plot file {plot_path} is missing."
    assert os.path.getsize(plot_path) > 0, f"Plot file {plot_path} is empty."

    # Verify it is a valid PNG file by checking the magic number
    with open(plot_path, 'rb') as f:
        header = f.read(8)
        assert header == b'\x89PNG\r\n\x1a\n', f"File {plot_path} is not a valid PNG image."

    # Decode and inspect the rendered chart for the required histogram and
    # fitted exponential PDF rather than accepting an arbitrary PNG.
    _validate_plot_contents(plot_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
