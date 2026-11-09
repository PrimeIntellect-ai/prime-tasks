#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os

import numpy as np
import pytest
from PIL import Image
from scipy import ndimage

OUTPUT_DIR = "/home/user/output"
JSON_FILE = os.path.join(OUTPUT_DIR, "analysis_results.json")
PNG_FILE = os.path.join(OUTPUT_DIR, "dominant_abundance.png")
CSV_FILE = "/home/user/data/viral_samples.csv"


def test_output_directory_exists():
    """Test that the output directory exists."""
    assert os.path.isdir(OUTPUT_DIR), f"The output directory {OUTPUT_DIR} does not exist."


def test_json_file_exists():
    """Test that the analysis_results.json file exists."""
    assert os.path.isfile(JSON_FILE), f"The JSON file {JSON_FILE} does not exist."


def test_png_file_exists():
    """Test that the dominant_abundance.png file exists."""
    assert os.path.isfile(PNG_FILE), f"The PNG file {PNG_FILE} does not exist."


def test_png_file_is_valid():
    """Test that the PNG file has the correct magic bytes."""
    with open(PNG_FILE, "rb") as f:
        header = f.read(8)
    # PNG magic number is \x89PNG\r\n\x1a\n
    assert header == b"\x89PNG\r\n\x1a\n", f"The file {PNG_FILE} is not a valid PNG image."


def _expected_abundances(sequence):
    rows = []
    with open(CSV_FILE, newline="") as f:
        for row in csv.DictReader(f):
            rows.append((int(row["Timepoint"]), row["Sequence"], float(row["Abundance"])))
    start = min(r[0] for r in rows)
    end = max(r[0] for r in rows)
    by_time = {t: 0.0 for t in range(start, end + 1)}
    for timepoint, seq, abundance in rows:
        if seq == sequence:
            by_time[timepoint] += abundance
    return np.asarray([by_time[t] for t in range(start, end + 1)], dtype=float)


def _profile_matches(values, expected, image_height):
    values = np.asarray(values, dtype=float)
    if len(values) != len(expected) or not np.all(np.isfinite(values)):
        return False
    if np.ptp(values) < max(4.0, image_height * 0.08):
        return False
    design = np.column_stack((expected, np.ones(len(expected))))
    slope, intercept = np.linalg.lstsq(design, values, rcond=None)[0]
    fitted = slope * expected + intercept
    residual = np.sum((values - fitted) ** 2)
    total = np.sum((values - values.mean()) ** 2)
    r_squared = 1.0 - residual / total if total > 0 else 0.0
    # Raster y coordinates run downward, so larger abundances must be higher.
    return slope < 0 and r_squared >= 0.90


def _mask_has_expected_trace(mask, expected):
    height, width = mask.shape
    ys, xs = np.nonzero(mask)
    if len(xs) < 20:
        return False
    x_span = int(xs.max() - xs.min())
    if x_span < width * 0.30:
        return False

    # Line and scatter plots: sample the trace at uniformly spaced timepoints.
    targets = np.linspace(xs.min(), xs.max(), len(expected))
    radius = max(2, int(round(x_span * 0.015)))
    for reducer in (np.median, np.min, np.max):
        profile = []
        for target in targets:
            local_y = ys[np.abs(xs - target) <= radius]
            if len(local_y) == 0:
                break
            profile.append(float(reducer(local_y)))
        if len(profile) == len(expected) and _profile_matches(profile, expected, height):
            return True

    # Bar plots: six separated runs of columns, using each bar's top edge.
    occupied = np.flatnonzero(mask.sum(axis=0) >= 2)
    if len(occupied):
        breaks = np.where(np.diff(occupied) > 1)[0] + 1
        runs = [r for r in np.split(occupied, breaks) if len(r) >= 2]
        if len(runs) == len(expected):
            tops = [float(np.nonzero(mask[:, run])[0].min()) for run in runs]
            if _profile_matches(tops, expected, height):
                return True
    return False


def _contains_expected_trace(rgb, expected):
    height, width, _ = rgb.shape
    colors, counts = np.unique(rgb.reshape(-1, 3), axis=0, return_counts=True)
    order = np.argsort(counts)[::-1]
    candidates = []
    for index in order:
        count = int(counts[index])
        if count < 20:
            break
        if count < height * width * 0.40:
            candidates.append(colors[index])
        if len(candidates) >= 64:
            break

    structure = np.ones((3, 3), dtype=int)
    for color in candidates:
        mask = np.all(rgb == color, axis=2)
        if _mask_has_expected_trace(mask, expected):
            return True
        labels, number = ndimage.label(mask, structure=structure)
        if number:
            sizes = np.bincount(labels.ravel())
            for label_id in np.argsort(sizes[1:])[-12:] + 1:
                if sizes[label_id] >= 20 and _mask_has_expected_trace(labels == label_id, expected):
                    return True
    return False


def test_png_decodes_and_plots_dominant_abundance():
    """Require a complete, nontrivial PNG containing the expected time-series trace."""
    try:
        with Image.open(PNG_FILE) as image:
            assert image.format == "PNG", "The visualization must be encoded as PNG."
            image.verify()
        with Image.open(PNG_FILE) as image:
            image.load()
            assert image.width >= 64 and image.height >= 64, "The visualization is too small to be a usable plot."
            if image.mode == "RGBA":
                background = Image.new("RGBA", image.size, (255, 255, 255, 255))
                background.alpha_composite(image)
                image = background.convert("RGB")
            else:
                image = image.convert("RGB")
            rgb = np.asarray(image)
    except Exception as exc:
        pytest.fail(f"The file {PNG_FILE} is not a complete, decodable PNG: {exc}")

    assert len(np.unique(rgb.reshape(-1, 3), axis=0)) >= 16, "The PNG does not contain a nontrivial plot."
    assert float(rgb.std()) >= 8.0, "The PNG is visually blank or nearly uniform."

    with open(JSON_FILE) as f:
        dominant = json.load(f)["dominant_sequence"]
    expected = _expected_abundances(dominant)
    assert _contains_expected_trace(rgb, expected), (
        "The PNG does not contain a line, scatter trace, or bar series matching the dominant "
        f"sequence abundances {expected.tolist()}."
    )


def test_json_content():
    """Test that the JSON file contains the correct analysis results."""
    with open(JSON_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_FILE} does not contain valid JSON.")

    expected_keys = {
        "largest_component_size",
        "dominant_sequence",
        "abundance_integral",
        "derivative_at_t_2"
    }

    assert set(data.keys()) == expected_keys, (
        f"The JSON file {JSON_FILE} does not have the exact expected keys. "
        f"Found: {list(data.keys())}, Expected: {list(expected_keys)}"
    )

    assert data["largest_component_size"] == 3, (
        f"Expected largest_component_size to be 3, got {data['largest_component_size']}."
    )

    assert data["dominant_sequence"] == "ACGTG", (
        f"Expected dominant_sequence to be 'ACGTG', got '{data['dominant_sequence']}'."
    )

    assert isinstance(data["abundance_integral"], (int, float)), "abundance_integral must be a float."
    assert round(data["abundance_integral"], 2) == 58.50, (
        f"Expected abundance_integral to be 58.50, got {data['abundance_integral']}."
    )

    assert isinstance(data["derivative_at_t_2"], (int, float)), "derivative_at_t_2 must be a float."
    assert round(data["derivative_at_t_2"], 2) == 1.00, (
        f"Expected derivative_at_t_2 to be 1.00, got {data['derivative_at_t_2']}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
