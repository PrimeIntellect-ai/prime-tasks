#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
import pytest
from sklearn.decomposition import PCA

RAW_PATH = "/home/user/dataset/sensors.csv"
AGG_PATH = "/home/user/dataset/aggregated.csv"
PLOT_PATH = "/home/user/results/pca_plot.png"
METRICS_PATH = "/home/user/results/metrics.json"
FEATURES = [f"reading_{i}" for i in range(1, 21)]


def expected_aggregation(raw_path=RAW_PATH):
    raw = pd.read_csv(raw_path)
    assert raw.shape[0] == 1000, "sensors.csv must contain 1000 data rows"
    assert list(raw.columns) == ["sensor_type"] + FEATURES, "sensors.csv has unexpected columns"
    return raw.groupby("sensor_type", as_index=False)[FEATURES].mean()


def assert_aggregation_correct(expected):
    actual = pd.read_csv(AGG_PATH)
    assert list(actual.columns) == ["sensor_type"] + FEATURES, "aggregated.csv has incorrect columns or column order"
    assert actual.shape == expected.shape, "aggregated.csv has an incorrect shape"
    assert actual["sensor_type"].is_unique, "aggregated.csv contains duplicate sensor types"
    assert set(actual["sensor_type"]) == set(expected["sensor_type"]), "aggregated.csv has incorrect sensor types"

    actual = actual.set_index("sensor_type").loc[expected["sensor_type"]]
    expected_values = expected.set_index("sensor_type")[FEATURES].to_numpy(dtype=float)
    actual_values = actual[FEATURES].to_numpy(dtype=float)
    np.testing.assert_allclose(
        actual_values,
        expected_values,
        rtol=1e-9,
        atol=1e-9,
        err_msg="aggregated.csv does not contain the grouped means from sensors.csv",
    )


def assert_metric_correct(expected):
    with open(METRICS_PATH, "r") as f:
        metrics = json.load(f)
    expected_sum = float(PCA(n_components=2).fit(expected[FEATURES]).explained_variance_ratio_.sum())
    assert np.isclose(metrics["explained_variance_sum"], expected_sum, rtol=1e-9, atol=1e-12), (
        f"Incorrect explained_variance_sum: expected {expected_sum}, "
        f"got {metrics['explained_variance_sum']}"
    )


def assert_valid_nonblank_png(path=PLOT_PATH):
    with open(path, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "pca_plot.png is not a PNG image"
    try:
        image = mpimg.imread(path)
    except Exception as exc:
        pytest.fail(f"pca_plot.png cannot be decoded as an image: {exc}")
    assert image.ndim in (2, 3), "pca_plot.png has an invalid image shape"
    assert image.shape[0] > 10 and image.shape[1] > 10, "pca_plot.png has invalid dimensions"
    assert np.isfinite(image).all(), "pca_plot.png contains invalid pixel values"
    visible = image[..., :3] if image.ndim == 3 and image.shape[2] >= 3 else image
    assert float(np.max(visible) - np.min(visible)) > 0.01, "pca_plot.png is visually blank"
    pixels = visible.reshape(-1, visible.shape[-1]) if visible.ndim == 3 else visible.reshape(-1, 1)
    assert np.unique(pixels, axis=0).shape[0] > 16, "pca_plot.png does not contain a nonblank rendered plot"


def test_makefile_exists():
    """Check if the Makefile was created."""
    assert os.path.isfile("/home/user/Makefile"), "Makefile is missing in /home/user."


def test_scripts_exist():
    """Check if the required Python scripts exist."""
    assert os.path.isfile("/home/user/scripts/aggregate.py"), "/home/user/scripts/aggregate.py is missing."
    assert os.path.isfile("/home/user/scripts/pca_plot.py"), "/home/user/scripts/pca_plot.py is missing."


def test_make_clean_and_all():
    """Test the Makefile clean and all targets."""
    if not os.path.isfile("/home/user/Makefile"):
        pytest.fail("Makefile is missing, cannot test targets.")

    result_clean = subprocess.run(
        ["make", "clean"], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert result_clean.returncode == 0, f"'make clean' failed: {result_clean.stderr.decode()}"

    assert not os.path.exists(AGG_PATH), "'make clean' did not remove aggregated.csv"
    assert not os.path.exists(PLOT_PATH), "'make clean' did not remove pca_plot.png"
    assert not os.path.exists(METRICS_PATH), "'make clean' did not remove metrics.json"

    result_all = subprocess.run(
        ["make"], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert result_all.returncode == 0, f"'make' failed: {result_all.stderr.decode()}"


def test_aggregated_csv_output():
    """Check if aggregated.csv is generated correctly after make."""
    assert os.path.isfile(AGG_PATH), f"{AGG_PATH} was not generated."

    with open(AGG_PATH, "r") as f:
        lines = f.readlines()

    assert len(lines) == 6, f"Expected 6 lines in {AGG_PATH}, but found {len(lines)}."

    header = lines[0].strip().split(",")
    assert "sensor_type" in header, "'sensor_type' column missing in aggregated.csv"
    for i in range(1, 21):
        assert f"reading_{i}" in header or f"reading_{i}" in lines[0], f"'reading_{i}' missing in aggregated.csv header."

    assert_aggregation_correct(expected_aggregation())


def test_pca_plot_output():
    """Check if pca_plot.png is generated and is a valid image file."""
    assert os.path.isfile(PLOT_PATH), f"{PLOT_PATH} was not generated."
    size = os.path.getsize(PLOT_PATH)
    assert size > 100, f"{PLOT_PATH} is too small ({size} bytes), likely an empty or corrupted image."
    assert_valid_nonblank_png()


def test_metrics_json_output():
    """Check if metrics.json is generated and contains the correct structure and value."""
    assert os.path.isfile(METRICS_PATH), f"{METRICS_PATH} was not generated."

    with open(METRICS_PATH, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{METRICS_PATH} does not contain valid JSON.")

    assert "explained_variance_sum" in metrics, "Key 'explained_variance_sum' missing in metrics.json."
    assert isinstance(metrics["explained_variance_sum"], float), "'explained_variance_sum' must be a float."
    assert 0.0 <= metrics["explained_variance_sum"] <= 1.0, "'explained_variance_sum' should be between 0.0 and 1.0."
    assert_metric_correct(expected_aggregation())


def test_pipeline_on_derived_input():
    """Exercise the pipeline on another input to reject hard-coded fabricated outputs."""
    with open(RAW_PATH, "rb") as f:
        original_raw = f.read()

    rng = np.random.default_rng(2026)
    sensor_types = np.repeat(["Type_A", "Type_B", "Type_C", "Type_D", "Type_E"], 200)
    rng.shuffle(sensor_types)
    bases = {name: value for name, value in zip(
        ["Type_A", "Type_B", "Type_C", "Type_D", "Type_E"],
        [3.0, 17.0, 29.0, 46.0, 71.0],
    )}
    heldout = {"sensor_type": sensor_types}
    base_values = np.array([bases[x] for x in sensor_types])
    for i in range(1, 21):
        heldout[f"reading_{i}"] = base_values * (0.35 + i / 17.0) + rng.normal(0, 1.0 + i / 20.0, 1000)
    heldout_df = pd.DataFrame(heldout)

    try:
        clean = subprocess.run(["make", "clean"], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert clean.returncode == 0, f"'make clean' failed on derived-input test: {clean.stderr.decode()}"
        heldout_df.to_csv(RAW_PATH, index=False)
        built = subprocess.run(["make"], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert built.returncode == 0, f"'make' failed on derived-input test: {built.stderr.decode()}"

        expected = expected_aggregation()
        assert_aggregation_correct(expected)
        assert_metric_correct(expected)
        assert os.path.getsize(PLOT_PATH) > 100
        assert_valid_nonblank_png()
    finally:
        with open(RAW_PATH, "wb") as f:
            f.write(original_raw)
        subprocess.run(["make", "clean"], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        subprocess.run(["make"], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
