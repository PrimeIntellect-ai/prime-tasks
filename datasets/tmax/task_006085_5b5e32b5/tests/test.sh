#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest
import numpy as np
import pandas as pd
import matplotlib.image as mpimg
from scipy import ndimage
from scipy.optimize import differential_evolution
from scipy.spatial import cKDTree


def test_singular_values_file_exists():
    """Verify that the singular_values.txt file exists."""
    file_path = "/home/user/singular_values.txt"
    assert os.path.exists(file_path), f"Missing required file: {file_path}"
    assert os.path.isfile(file_path), f"Path exists but is not a file: {file_path}"


def test_singular_values_content():
    """Verify the contents of singular_values.txt match the expected singular values."""
    file_path = "/home/user/singular_values.txt"
    assert os.path.exists(file_path), f"Missing required file: {file_path}"

    expected_values = [
        "16.4827",
        "11.6033",
        "1.1416",
        "0.9996",
        "0.8711"
    ]

    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == len(expected_values), f"Expected {len(expected_values)} singular values, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_values)):
        assert actual == expected, f"Mismatch at line {i+1}: expected {expected}, got {actual}."


def _component_centers(mask):
    """Return centers of marker-sized connected foreground components."""
    labels, count = ndimage.label(mask, structure=np.ones((3, 3), dtype=int))
    objects = ndimage.find_objects(labels)
    centers = []
    h, w = mask.shape
    max_span = max(30, int(0.08 * min(h, w)))

    for label_id, slc in enumerate(objects, start=1):
        if slc is None:
            continue
        ys, xs = slc
        ch, cw = ys.stop - ys.start, xs.stop - xs.start
        area = int(np.count_nonzero(labels[slc] == label_id))
        # Reject isolated antialiasing pixels and long axes/grid lines.
        if area < 3 or area > 1500 or ch > max_span or cw > max_span:
            continue
        cy, cx = ndimage.center_of_mass(mask, labels, label_id)
        if np.isfinite(cx) and np.isfinite(cy):
            centers.append((cx, cy))
    return np.asarray(centers, dtype=float)


def _projection_matches_scatter(rgb, projection):
    """Check that marker locations have the geometry of the required projection."""
    h, w, _ = rgb.shape

    # Colored markers are the normal matplotlib output and avoid confusing black
    # tick-label glyphs with points. A grayscale fallback permits black markers.
    chroma = rgb.max(axis=2) - rgb.min(axis=2)
    colored = (chroma > 0.08) & (rgb.min(axis=2) < 0.96)
    centers = _component_centers(colored)

    if len(centers) < 20:
        gray = rgb.mean(axis=2)
        dark = gray < 0.65
        centers = _component_centers(dark)

    if len(centers) < 20:
        return False, f"found only {len(centers)} marker-like objects"

    tree = cKDTree(centers)
    radius = max(6.0, 0.016 * min(h, w))
    best_coverage = 0.0
    best_median = float('inf')

    # SVD component signs are arbitrary, so accept all PC sign combinations.
    for sx in (1.0, -1.0):
        for sy in (1.0, -1.0):
            z = projection * np.array([sx, sy])
            q = (z - z.min(axis=0)) / np.ptp(z, axis=0)

            # Fit only the ordinary axis-aligned data-to-pixel transform. Bounds
            # allow normal, tight-layout, and modestly customized plot margins.
            def distances(params):
                left, right, top, bottom = params
                if right <= left + 0.35 * w or bottom <= top + 0.35 * h:
                    return None
                points = np.column_stack((
                    left + q[:, 0] * (right - left),
                    bottom - q[:, 1] * (bottom - top),
                ))
                return tree.query(points, k=1)[0]

            def objective(params):
                d = distances(params)
                if d is None:
                    return 10.0
                return float(np.mean(np.minimum(d / radius, 1.5)))

            result = differential_evolution(
                objective,
                bounds=[(0.02*w, 0.35*w), (0.65*w, 0.99*w),
                        (0.01*h, 0.35*h), (0.65*h, 0.99*h)],
                seed=1234, popsize=10, maxiter=80, polish=True,
                updating='immediate', workers=1,
            )
            d = distances(result.x)
            if d is not None:
                best_coverage = max(best_coverage, float(np.mean(d <= radius)))
                best_median = min(best_median, float(np.median(d)))

    return (best_coverage >= 0.60 and best_median <= radius), \
           f"best point coverage={best_coverage:.3f}, median error={best_median:.2f}px"


def test_pca_plot_exists_and_valid():
    """Verify that pca_plot.png is a decodable scatter of the required PC projection."""
    file_path = "/home/user/pca_plot.png"
    assert os.path.exists(file_path), f"Missing required file: {file_path}"
    assert os.path.isfile(file_path), f"Path exists but is not a file: {file_path}"
    assert os.path.getsize(file_path) > 0, f"File is empty: {file_path}"

    # Keep the original PNG magic-number assertion.
    with open(file_path, 'rb') as f:
        header = f.read(8)
    assert header == b'\x89PNG\r\n\x1a\n', f"File {file_path} is not a valid PNG image."

    # Decode the complete image so a malformed file with only a PNG header fails.
    try:
        image = mpimg.imread(file_path)
    except Exception as exc:
        pytest.fail(f"File {file_path} is not a decodable PNG image: {exc}")

    assert image.ndim in (2, 3), f"Unexpected image shape: {image.shape}"
    if image.ndim == 2:
        image = np.repeat(image[:, :, None], 3, axis=2)
    if image.shape[2] == 4:
        alpha = image[:, :, 3:4].astype(float)
        image = image[:, :, :3].astype(float) * alpha + (1.0 - alpha)
    else:
        image = image[:, :, :3].astype(float)
    if image.max() > 1.0:
        image /= 255.0

    assert image.shape[0] >= 64 and image.shape[1] >= 64, \
        f"Plot image is too small to contain the required scatter: {image.shape}"
    assert float(np.std(image)) > 0.01, "Plot image is visually blank."

    # Independently derive the required PC1/PC2 coordinates from the supplied data.
    data = pd.read_csv('/home/user/sensor_data.csv')
    wide = data.pivot(index='time', columns='sensor', values='reading')
    wide = wide.sort_index().reindex(sorted(wide.columns), axis=1)
    centered = wide.to_numpy(dtype=float) - wide.to_numpy(dtype=float).mean(axis=0)
    u, s, vt = np.linalg.svd(centered, full_matrices=False)
    expected_projection = u[:, :2] * s[:2]

    matches, detail = _projection_matches_scatter(image, expected_projection)
    assert matches, f"PNG does not contain the required PC1/PC2 scatter ({detail})."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
