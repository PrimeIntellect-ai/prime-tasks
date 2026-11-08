#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt, maximum_filter, minimum_filter
from scipy.optimize import differential_evolution


def test_correlation_file_content():
    corr_file = "/home/user/correlation.txt"
    assert os.path.isfile(corr_file), f"Correlation file {corr_file} is missing."

    with open(corr_file, "r") as f:
        content = f.read().strip()

    # The expected correlation is 0.9859 based on the deterministic data generation
    # X = [1.0, 2.0, ..., 50.0]
    # Y = [0.5 * X_i + (X_i % 4)]
    expected_corr = "0.9859"

    assert content == expected_corr, f"Expected correlation value '{expected_corr}', but got '{content}'."


def test_scatter_plot_exists_and_size():
    scatter_file = "/home/user/scatter.png"
    assert os.path.isfile(scatter_file), f"Scatter plot file {scatter_file} is missing."

    size = os.path.getsize(scatter_file)
    assert size > 100, f"Scatter plot file {scatter_file} is too small ({size} bytes), likely blank or invalid."


def test_scatter_plot_is_png():
    scatter_file = "/home/user/scatter.png"
    assert os.path.isfile(scatter_file), f"Scatter plot file {scatter_file} is missing."

    with open(scatter_file, "rb") as f:
        header = f.read(8)

    # PNG magic number: \x89PNG\r\n\x1a\n
    expected_magic = b"\x89PNG\r\n\x1a\n"
    assert header == expected_magic, f"Scatter plot file {scatter_file} is not a valid PNG image based on its magic bytes."


def test_scatter_plot_contains_supplied_data():
    # Read all supplied runs and independently derive the point coordinates.
    paths = sorted(glob.glob("/home/user/logs/*.json"))
    assert len(paths) == 50, f"Expected 50 JSON run files, found {len(paths)}."

    points = []
    for path in paths:
        with open(path, "r") as f:
            data = json.load(f)
        points.append((float(data["metrics"]["training_time"]),
                       float(data["metrics"]["val_loss"])))

    points.sort()
    expected_points = [(float(i), 0.5 * i + (i % 4)) for i in range(1, 51)]
    assert points == expected_points, "The supplied experiment inputs were modified."

    xs = np.array([p[0] for p in points], dtype=float)
    ys = np.array([p[1] for p in points], dtype=float)
    xn = (xs - xs.min()) / (xs.max() - xs.min())
    yn = (ys - ys.min()) / (ys.max() - ys.min())

    # Decode the image rather than trusting only its PNG signature.
    with Image.open("/home/user/scatter.png") as image:
        image.load()
        rgba = np.asarray(image.convert("RGBA"), dtype=np.uint8)

    h, w = rgba.shape[:2]
    assert w >= 100 and h >= 100, f"Scatter plot dimensions are too small: {w}x{h}."

    # Composite transparency onto white and identify rendered edges. This is
    # independent of marker color and works with light or dark plotting themes.
    rgb = rgba[:, :, :3].astype(float)
    alpha = rgba[:, :, 3:4].astype(float) / 255.0
    rgb = rgb * alpha + 255.0 * (1.0 - alpha)
    channel_range = maximum_filter(rgb, size=(3, 3, 1)) - minimum_filter(rgb, size=(3, 3, 1))
    rendered = np.max(channel_range, axis=2) > 18.0
    rendered_fraction = float(rendered.mean())
    assert 0.0005 < rendered_fraction < 0.35, "Scatter image is blank or does not resemble a rendered plot."

    # Find the affine plot-area mapping that best aligns image marks with the
    # 50 expected points. Pixel coordinates may vary with plotting library,
    # margins, labels, and axis limits, but data coordinates must retain this
    # affine relationship.
    distances = distance_transform_edt(~rendered)

    bounds = [
        (0.03 * w, 0.30 * w),  # pixel x of minimum training_time
        (0.65 * w, 0.98 * w),  # pixel x of maximum training_time
        (0.02 * h, 0.38 * h),  # pixel y of maximum val_loss
        (0.60 * h, 0.98 * h),  # pixel y of minimum val_loss
    ]

    def objective(params):
        left, right, top, bottom = params
        if right - left < 0.35 * w or bottom - top < 0.30 * h:
            return 1000.0
        px = np.rint(left + (right - left) * xn).astype(int)
        py = np.rint(bottom - (bottom - top) * yn).astype(int)
        px = np.clip(px, 0, w - 1)
        py = np.clip(py, 0, h - 1)
        return float(np.minimum(distances[py, px], 12.0).mean())

    result = differential_evolution(
        objective,
        bounds,
        seed=1729,
        maxiter=180,
        popsize=18,
        tol=0.01,
        polish=True,
        workers=1,
    )

    left, right, top, bottom = result.x
    px = np.rint(left + (right - left) * xn).astype(int)
    py = np.rint(bottom - (bottom - top) * yn).astype(int)
    px = np.clip(px, 0, w - 1)
    py = np.clip(py, 0, h - 1)
    point_distances = distances[py, px]
    radius = max(3.0, 0.012 * min(w, h))
    matched = int(np.count_nonzero(point_distances <= radius))

    assert matched >= 44, (
        f"Only {matched}/50 expected data locations align with plotted marks; "
        "scatter.png does not appear to plot the supplied training_time and val_loss data."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
