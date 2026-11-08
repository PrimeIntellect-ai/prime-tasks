#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest
import numpy as np
from PIL import Image, UnidentifiedImageError


def test_fit_comparison_png_exists():
    file_path = "/home/user/fit_comparison.png"
    assert os.path.exists(file_path), f"The plot file {file_path} does not exist."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."


def test_fit_comparison_is_meaningful_png():
    file_path = "/home/user/fit_comparison.png"

    try:
        with Image.open(file_path) as image:
            assert image.format == "PNG", f"The plot file {file_path} is not a PNG image."
            image.verify()
        with Image.open(file_path) as image:
            rgba = np.asarray(image.convert("RGBA"), dtype=np.float32)
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        pytest.fail(f"The plot file {file_path} is not a valid, readable PNG: {exc}")

    height, width = rgba.shape[:2]
    assert width >= 300 and height >= 200, (
        f"The plot image is too small to contain a useful comparison: {width}x{height}."
    )

    # Composite transparency over white, then estimate the background from corners.
    alpha = rgba[:, :, 3:4] / 255.0
    rgb = rgba[:, :, :3] * alpha + 255.0 * (1.0 - alpha)
    corner = max(5, min(width, height) // 40)
    corners = np.concatenate([
        rgb[:corner, :corner].reshape(-1, 3),
        rgb[:corner, -corner:].reshape(-1, 3),
        rgb[-corner:, :corner].reshape(-1, 3),
        rgb[-corner:, -corner:].reshape(-1, 3),
    ])
    background = np.median(corners, axis=0)
    foreground = np.max(np.abs(rgb - background), axis=2) > 18.0

    assert foreground.mean() >= 0.005, "The PNG is blank or contains too little plotted content."
    assert float(np.std(rgb)) >= 3.0, "The PNG has insufficient visual variation for a plot."

    # Inspect the central plotting region. Remove long straight grid/spine lines and
    # require curve-like content across the time axis, with two separated traces in
    # a meaningful subset of columns (experimental data and fitted trajectory).
    y0, y1 = int(height * 0.10), int(height * 0.90)
    x0, x1 = int(width * 0.10), int(width * 0.90)
    plot_mask = foreground[y0:y1, x0:x1].copy()
    ph, pw = plot_mask.shape

    horizontal_lines = plot_mask.sum(axis=1) > 0.70 * pw
    vertical_lines = plot_mask.sum(axis=0) > 0.70 * ph
    plot_mask[horizontal_lines, :] = False
    plot_mask[:, vertical_lines] = False

    occupied_columns = np.count_nonzero(plot_mask.any(axis=0))
    assert occupied_columns >= 0.45 * pw, (
        "The PNG does not contain curve-like plotted data across the time axis."
    )

    columns_with_two_traces = 0
    for column in plot_mask.T:
        ys = np.flatnonzero(column)
        if ys.size < 2:
            continue
        # Separate runs by at least two background pixels so antialiasing/thickness
        # of one line is not mistaken for two compared trajectories.
        if np.any(np.diff(ys) >= 3):
            columns_with_two_traces += 1

    assert columns_with_two_traces >= 0.10 * pw, (
        "The PNG does not show both experimental data and a fitted trajectory."
    )


def test_model_params_json_exists():
    file_path = "/home/user/model_params.json"
    assert os.path.exists(file_path), f"The parameters file {file_path} does not exist."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."


def test_model_params_content():
    file_path = "/home/user/model_params.json"
    assert os.path.exists(file_path), f"The parameters file {file_path} does not exist."

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} is not a valid JSON file.")

    expected = {"omega": 15.0, "c": 0.8, "k": 25.0, "F": 3.5}
    tolerances = {"omega": 0.5, "c": 0.2, "k": 1.0, "F": 0.5}

    for key in expected:
        assert key in data, f"Missing key '{key}' in {file_path}."

        val = data[key]
        assert isinstance(val, (int, float)), f"Value for '{key}' must be a number, got {type(val)}."

        diff = abs(val - expected[key])
        assert diff <= tolerances[key], (
            f"Value for '{key}' is out of bounds. "
            f"Expected ~{expected[key]} (±{tolerances[key]}), got {val}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
