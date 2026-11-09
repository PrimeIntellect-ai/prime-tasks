#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import math
import numpy as np
from PIL import Image, ImageFilter


def _plot_matches_cleaned_data(plot_path):
    # Decode the artifact as a real PNG rather than trusting its extension/size.
    with Image.open(plot_path) as image:
        assert image.format == 'PNG', f"Expected {plot_path} to be a PNG image, got {image.format}."
        image.verify()

    with Image.open(plot_path) as image:
        rgba = image.convert('RGBA')
        assert rgba.width >= 200 and rgba.height >= 150, "Scatter plot image has implausibly small dimensions."
        background = Image.new('RGBA', rgba.size, (255, 255, 255, 255))
        background.alpha_composite(rgba)
        rgb = np.asarray(background.convert('RGB'))

    with open('/home/user/cleaned_data.csv', 'r', newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['A', 'B', 'C']
        points = [(float(row['B']), float(row['C'])) for row in reader]

    points = [(x, y) for x, y in points if math.isfinite(x) and math.isfinite(y)]
    assert len(points) >= 2, "Not enough finite B/C values to verify the scatter plot."
    xs = np.asarray([p[0] for p in points], dtype=float)
    ys = np.asarray([p[1] for p in points], dtype=float)
    assert np.ptp(xs) > 0 and np.ptp(ys) > 0, "B and C must span nonzero ranges."

    # Select relatively uncommon colors as plot ink. This removes solid figure and
    # axes backgrounds while retaining markers, marker edges, labels, and spines.
    quantized = (rgb[:, :, 0] // 16) * 256 + (rgb[:, :, 1] // 16) * 16 + (rgb[:, :, 2] // 16)
    counts = np.bincount(quantized.ravel(), minlength=4096)
    ink = counts[quantized] < max(2, int(rgb.shape[0] * rgb.shape[1] * 0.02))

    # Remove long grid/spine lines so matching is driven by point marks rather than axes.
    row_counts = ink.sum(axis=1)
    col_counts = ink.sum(axis=0)
    ink[row_counts > rgb.shape[1] * 0.35, :] = False
    ink[:, col_counts > rgb.shape[0] * 0.35] = False

    h, w = ink.shape
    assert ink.sum() > 25, "Scatter plot is blank or contains no detectable plotted marks."

    radius = max(4, int(round(min(h, w) * 0.015)))
    if radius % 2 == 0:
        radius += 1
    nearby_ink = np.asarray(
        Image.fromarray((ink.astype(np.uint8) * 255)).filter(ImageFilter.MaxFilter(radius)),
        dtype=np.uint8,
    ) > 0

    xnorm = (xs - xs.min()) / np.ptp(xs)
    ynorm = (ys - ys.min()) / np.ptp(ys)

    # Plot style and margins are unrestricted, so search plausible affine mappings
    # from data coordinates into the image. A genuine B-versus-C scatter places ink
    # near most transformed data points; an unrelated plot does not.
    x_min_positions = np.linspace(0.04 * w, 0.45 * w, 19)
    x_max_positions = np.linspace(0.55 * w, 0.96 * w, 19)
    y_max_positions = np.linspace(0.04 * h, 0.42 * h, 19)
    y_min_positions = np.linspace(0.58 * h, 0.96 * h, 19)

    best_score = -1.0
    best_bounds = None
    for x_min_px in x_min_positions:
        for x_max_px in x_max_positions:
            px = np.rint(x_min_px + xnorm * (x_max_px - x_min_px)).astype(int)
            px = np.clip(px, 0, w - 1)
            for y_max_px in y_max_positions:
                for y_min_px in y_min_positions:
                    py = np.rint(y_min_px - ynorm * (y_min_px - y_max_px)).astype(int)
                    py = np.clip(py, 0, h - 1)
                    score = float(nearby_ink[py, px].mean())
                    if score > best_score:
                        best_score = score
                        best_bounds = (x_min_px, x_max_px, y_max_px, y_min_px)

    assert best_score >= 0.65, (
        f"PNG does not depict the required scatter plot of cleaned B versus C "
        f"(only {best_score:.1%} of expected points matched plotted marks)."
    )

    left, right, top, bottom = best_bounds
    region = ink[max(0, int(top)):min(h, int(bottom) + 1),
                 max(0, int(left)):min(w, int(right) + 1)]
    assert region.size and float(region.mean()) < 0.35, (
        "Image content is too dense to be a recognizable scatter plot; expected-point "
        "matching appears to come from an unrelated image or filled region."
    )


def test_scatter_plot_exists():
    plot_path = '/home/user/scatter.png'
    assert os.path.isfile(plot_path), f"Expected plot file {plot_path} does not exist."
    assert os.path.getsize(plot_path) > 1000, f"Plot file {plot_path} is too small to be a valid image."
    _plot_matches_cleaned_data(plot_path)


def get_percentile(data, q):
    if not data:
        return None
    data = sorted(data)
    n = len(data)
    p = (n - 1) * q
    i = int(p)
    f = p - i
    if i + 1 < n:
        return (1 - f) * data[i] + f * data[i + 1]
    else:
        return data[i]


def test_cleaned_data_correct():
    raw_path = '/home/user/raw_data.csv'
    cleaned_path = '/home/user/cleaned_data.csv'

    assert os.path.isfile(cleaned_path), f"Expected cleaned data file {cleaned_path} does not exist."

    with open(raw_path, 'r', newline='') as f:
        reader = csv.reader(f)
        headers = next(reader)

        try:
            idx_a = headers.index('A')
            idx_b = headers.index('B')
            idx_c = headers.index('C')
        except ValueError as e:
            assert False, f"Raw data missing required columns: {e}"

        raw_rows = list(reader)

    # 1. Drop rows where A is NaN
    filtered_rows = []
    for row in raw_rows:
        val_a = row[idx_a]
        if val_a.strip().lower() in ('', 'nan'):
            continue
        filtered_rows.append(row)

    # 2. Fill missing B with mean of remaining B
    b_values = []
    for row in filtered_rows:
        val_b = row[idx_b]
        if val_b.strip().lower() not in ('', 'nan'):
            b_values.append(float(val_b))

    b_mean = sum(b_values) / len(b_values) if b_values else 0.0

    # 3. Clip C to 5th and 95th percentiles
    c_values = []
    for row in filtered_rows:
        val_c = row[idx_c]
        if val_c.strip().lower() not in ('', 'nan'):
            c_values.append(float(val_c))

    p5 = get_percentile(c_values, 0.05)
    p95 = get_percentile(c_values, 0.95)

    expected_data = []
    for row in filtered_rows:
        a = float(row[idx_a])

        val_b = row[idx_b]
        if val_b.strip().lower() in ('', 'nan'):
            b = b_mean
        else:
            b = float(val_b)

        val_c = row[idx_c]
        if val_c.strip().lower() in ('', 'nan'):
            c = float('nan')
        else:
            c = float(val_c)
            if c < p5:
                c = p5
            elif c > p95:
                c = p95

        expected_data.append((a, b, c))

    # Read cleaned data and verify
    with open(cleaned_path, 'r', newline='') as f:
        reader = csv.reader(f)
        cleaned_headers = next(reader)
        assert cleaned_headers == ['A', 'B', 'C'], f"Cleaned data headers should be ['A', 'B', 'C'], got {cleaned_headers}"

        cleaned_rows = list(reader)

    assert len(cleaned_rows) == len(expected_data), f"Expected {len(expected_data)} rows in cleaned data, got {len(cleaned_rows)}"

    for i, (exp, act) in enumerate(zip(expected_data, cleaned_rows)):
        try:
            act_a, act_b, act_c = float(act[0]), float(act[1]), float(act[2])
        except ValueError:
            assert False, f"Row {i+1} in cleaned data contains non-float values: {act}"

        assert math.isclose(act_a, exp[0], rel_tol=1e-4, abs_tol=1e-4), f"Row {i+1} Col A mismatch: expected {exp[0]}, got {act_a}"
        assert math.isclose(act_b, exp[1], rel_tol=1e-4, abs_tol=1e-4), f"Row {i+1} Col B mismatch: expected {exp[1]}, got {act_b}"
        assert math.isclose(act_c, exp[2], rel_tol=1e-4, abs_tol=1e-4), f"Row {i+1} Col C mismatch: expected {exp[2]}, got {act_c}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
