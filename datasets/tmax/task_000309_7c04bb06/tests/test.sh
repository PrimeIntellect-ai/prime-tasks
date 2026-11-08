#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import json
import math
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
import requests
from PIL import Image, ImageChops
from scipy import stats

BASE_URL = "http://127.0.0.1:8080"
HEADERS = {"X-Research-Token": "sigma-99-alpha"}
DATA_PATH = Path("/home/user/data/texts.csv")
PLOT_PATH = Path("/home/user/plot.png")
SOURCE_PACKAGE = Path("/app/research-viz-pkg/research_viz/plot_utils.py")


def compute_expected():
    frame = pd.read_csv(DATA_PATH)
    assert list(frame.columns) == ["group", "text"]

    def document_mean(text):
        cleaned = str(text).lower()
        for character in ".,!?”":
            cleaned = cleaned.replace(character, "")
        tokens = cleaned.split()
        assert tokens, "Every input document must contain at least one token"
        return sum(map(len, tokens)) / len(tokens)

    means = frame["text"].map(document_mean)
    control = means[frame["group"] == "Control"].to_numpy(dtype=float)
    treatment = means[frame["group"] == "Treatment"].to_numpy(dtype=float)
    assert len(control) >= 2 and len(treatment) >= 2

    result = stats.ttest_ind(treatment, control, equal_var=False)
    control_var = np.var(control, ddof=1)
    treatment_var = np.var(treatment, ddof=1)
    se2 = treatment_var / len(treatment) + control_var / len(control)
    se = math.sqrt(se2)
    df = se2 ** 2 / (
        (treatment_var / len(treatment)) ** 2 / (len(treatment) - 1)
        + (control_var / len(control)) ** 2 / (len(control) - 1)
    )
    difference = float(np.mean(treatment) - np.mean(control))
    critical = float(stats.t.ppf(0.975, df))
    expected = {
        "t_stat": round(float(result.statistic), 4),
        "p_value": round(float(result.pvalue), 4),
        "ci_lower": round(difference - critical * se, 4),
        "ci_upper": round(difference + critical * se, 4),
    }
    return control.tolist(), treatment.tolist(), expected


CONTROL, TREATMENT, EXPECTED_STATS = compute_expected()


def assert_nonblank_png(path):
    path = Path(path)
    assert path.is_file(), f"Missing PNG file: {path}"
    raw = path.read_bytes()
    assert len(raw) > 1000, f"PNG is too small ({len(raw)} bytes): {path}"
    assert raw.startswith(b"\x89PNG\r\n\x1a\n"), f"Invalid PNG signature: {path}"
    with Image.open(path) as image:
        assert image.format == "PNG"
        rgb = image.convert("RGB")
        extrema = rgb.getextrema()
        assert any(low != high for low, high in extrema), f"PNG is blank: {path}"
        colors = rgb.getcolors(maxcolors=10_000_000)
        assert colors is None or len(colors) > 10, f"PNG is virtually empty: {path}"


def generate_with_installed_package(control, treatment, output):
    code = r'''
import json
import sys
from research_viz.plot_utils import generate_boxplot
control = json.loads(sys.argv[1])
treatment = json.loads(sys.argv[2])
generate_boxplot(control, treatment, sys.argv[3])
'''
    env = os.environ.copy()
    env.pop("DISPLAY", None)
    env.pop("PYTHONPATH", None)
    subprocess.run(
        [sys.executable, "-c", code, json.dumps(control), json.dumps(treatment), str(output)],
        cwd="/tmp",
        env=env,
        check=True,
        timeout=20,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_auth_required_stats():
    try:
        response = requests.get(f"{BASE_URL}/stats", timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}/stats: {exc}")
    assert response.status_code in (401, 403), (
        f"Expected 401 or 403 when accessing /stats without auth, got {response.status_code}"
    )


def test_auth_required_plot():
    try:
        response = requests.get(f"{BASE_URL}/plot", timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}/plot: {exc}")
    assert response.status_code in (401, 403), (
        f"Expected 401 or 403 when accessing /plot without auth, got {response.status_code}"
    )


def test_stats_endpoint():
    try:
        response = requests.get(f"{BASE_URL}/stats", headers=HEADERS, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}/stats: {exc}")

    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response from /stats, got: {response.text}")

    expected_keys = {"t_stat", "p_value", "ci_lower", "ci_upper"}
    assert set(data.keys()) == expected_keys, f"Expected keys {expected_keys}, got {set(data.keys())}"
    for key in expected_keys:
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), (
            f"Expected {key} to be a number, got {type(data[key])}"
        )
        assert math.isfinite(float(data[key])), f"Expected finite {key}, got {data[key]}"

    # Preserve the original broad assertions.
    assert abs(data["t_stat"] - 13.0673) < 1.0
    assert data["p_value"] < 0.05
    assert data["ci_lower"] > 0
    assert data["ci_upper"] > data["ci_lower"]

    # Recompute all requested statistics from the supplied CSV and enforce rounding.
    assert data == EXPECTED_STATS, f"Expected recomputed statistics {EXPECTED_STATS}, got {data}"


def test_package_is_fixed_installed_and_functional():
    assert SOURCE_PACKAGE.is_file(), f"Missing vendored package source: {SOURCE_PACKAGE}"
    try:
        assert importlib.metadata.version("research-viz-pkg") == "1.0.0"
    except importlib.metadata.PackageNotFoundError:
        pytest.fail("research-viz-pkg is not installed")

    with tempfile.TemporaryDirectory() as directory:
        source_output = Path(directory) / "source.png"
        code = r'''
import json
import matplotlib
import sys
from research_viz.plot_utils import generate_boxplot
generate_boxplot([1.0, 2.0, 3.0], [8.0, 9.0, 10.0], sys.argv[1])
print(json.dumps({"backend": matplotlib.get_backend()}))
'''
        env = os.environ.copy()
        env.pop("DISPLAY", None)
        env["PYTHONPATH"] = "/app/research-viz-pkg"
        result = subprocess.run(
            [sys.executable, "-c", code, str(source_output)],
            cwd="/tmp",
            env=env,
            check=True,
            timeout=20,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        report = json.loads(result.stdout.strip().splitlines()[-1])
        assert str(report["backend"]).lower() != "template", "Vendored source still uses Template backend"
        assert_nonblank_png(source_output)

        installed_output = Path(directory) / "installed.png"
        changed_output = Path(directory) / "changed.png"
        generate_with_installed_package(CONTROL, TREATMENT, installed_output)
        generate_with_installed_package([1.0, 1.2, 1.4], [20.0, 21.0, 22.0], changed_output)
        assert_nonblank_png(installed_output)
        assert_nonblank_png(changed_output)

        with Image.open(installed_output) as first, Image.open(changed_output) as second:
            difference = ImageChops.difference(first.convert("RGBA"), second.convert("RGBA"))
            assert difference.getbbox() is not None, "generate_boxplot output does not respond to its data"


def test_plot_endpoint_and_artifact():
    assert_nonblank_png(PLOT_PATH)

    try:
        response = requests.get(f"{BASE_URL}/plot", headers=HEADERS, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}/plot: {exc}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    content_type = response.headers.get("Content-Type", "")
    assert "image/png" in content_type.lower(), f"Expected Content-Type image/png, got {content_type}"
    assert len(response.content) > 1000, f"Plot image is too small ({len(response.content)} bytes)"
    assert response.content.startswith(b"\x89PNG\r\n\x1a\n"), "Response lacks PNG magic bytes"
    assert response.content == PLOT_PATH.read_bytes(), "/plot does not serve /home/user/plot.png"

    # Re-run the installed proprietary function on values derived from the CSV and
    # require the saved artifact to have the same rendered pixels.
    with tempfile.TemporaryDirectory() as directory:
        expected_plot = Path(directory) / "expected.png"
        generate_with_installed_package(CONTROL, TREATMENT, expected_plot)
        assert_nonblank_png(expected_plot)
        with Image.open(PLOT_PATH) as actual, Image.open(expected_plot) as expected:
            assert actual.size == expected.size
            difference = ImageChops.difference(actual.convert("RGBA"), expected.convert("RGBA"))
            assert difference.getbbox() is None, (
                "/home/user/plot.png is not the boxplot produced by generate_boxplot "
                "for the CSV-derived group values"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
