#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_analyze_instrumented.py
import json
import os
import runpy

import matplotlib
matplotlib.use("Agg")
from matplotlib.axes import Axes
from matplotlib.figure import Figure
from matplotlib.container import BarContainer

telemetry_path = os.environ["ANALYZE_TELEMETRY"]
telemetry = {"hist_calls": [], "saves": []}
axis_ids = {}


def axis_id(ax):
    key = id(ax)
    if key not in axis_ids:
        axis_ids[key] = len(axis_ids)
    return axis_ids[key]


def normalized_labels(value):
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    try:
        return [str(item) for item in value]
    except TypeError:
        return [str(value)]


def normalized_bins(value):
    if value is None:
        return None
    try:
        if isinstance(value, (int, float)):
            return int(value)
        return {"edges": len(value)}
    except Exception:
        return str(value)


original_hist = Axes.hist
original_savefig = Figure.savefig


def recording_hist(self, *args, **kwargs):
    result = original_hist(self, *args, **kwargs)
    patches = result[2]
    datasets = 1 if isinstance(patches, BarContainer) else len(patches)
    bins = kwargs.get("bins", args[1] if len(args) > 1 else None)
    telemetry["hist_calls"].append({
        "axis": axis_id(self),
        "datasets": datasets,
        "bins": normalized_bins(bins),
        "alpha": kwargs.get("alpha"),
        "labels": normalized_labels(kwargs.get("label")),
    })
    return result


def recording_savefig(self, fname, *args, **kwargs):
    axes = []
    for ax in self.axes:
        half_alpha_patches = 0
        for patch in ax.patches:
            alpha = patch.get_alpha()
            if alpha is None:
                try:
                    alpha = patch.get_facecolor()[3]
                except Exception:
                    alpha = None
            if alpha is not None and abs(float(alpha) - 0.5) < 1e-9:
                half_alpha_patches += 1
        legend = ax.get_legend()
        legend_labels = []
        if legend is not None:
            legend_labels = [text.get_text() for text in legend.get_texts()]
        axes.append({
            "axis": axis_id(ax),
            "patch_count": len(ax.patches),
            "half_alpha_patches": half_alpha_patches,
            "legend_labels": legend_labels,
        })
    telemetry["saves"].append({"path": str(fname), "axes": axes})
    return original_savefig(self, fname, *args, **kwargs)


Axes.hist = recording_hist
Figure.savefig = recording_savefig
try:
    runpy.run_path("/home/user/analyze_sim.py", run_name="__main__")
finally:
    with open(telemetry_path, "w", encoding="utf-8") as f:
        json.dump(telemetry, f)
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import tempfile

import matplotlib.image as mpimg
import numpy as np

SCRIPT = "/home/user/analyze_sim.py"
SINGLE = "/home/user/single_thread.csv"
MULTI = "/home/user/multi_thread.csv"
TXT = "/home/user/wasserstein.txt"
PNG = "/home/user/distributions.png"


def expected_distance(single, multi):
    return float(np.mean(np.abs(np.sort(single) - np.sort(multi))))


def assert_real_png(path):
    assert os.path.isfile(path), f"The plot {path} does not exist."
    with open(path, "rb") as f:
        header = f.read(8)
    assert header == b"\x89PNG\r\n\x1a\n", f"The file {path} is not a valid PNG image."
    image = mpimg.imread(path)
    assert image.ndim in (2, 3), "The PNG could not be decoded as an image."
    assert image.shape[0] >= 100 and image.shape[1] >= 100, "The plot image is implausibly small."
    assert float(np.var(image.astype(float))) > 1e-6, "The plot image has no meaningful visual content."


def assert_histogram_telemetry(telemetry):
    qualifying_axis = False
    for axis in {call["axis"] for call in telemetry["hist_calls"]}:
        calls = [call for call in telemetry["hist_calls"] if call["axis"] == axis]
        if sum(call["datasets"] for call in calls) < 2:
            continue
        bins_ok = all(
            call["bins"] == 50 or
            (isinstance(call["bins"], dict) and call["bins"].get("edges") == 51)
            for call in calls
        )
        alpha_ok = all(call["alpha"] is not None and abs(float(call["alpha"]) - 0.5) < 1e-9 for call in calls)
        if bins_ok and alpha_ok:
            qualifying_axis = True
            break

    # Also permit implementations that explicitly construct histogram bars rather
    # than calling Axes.hist, provided they produce two sets of 50 half-alpha bars.
    artist_axis = any(
        axis["patch_count"] >= 100 and axis["half_alpha_patches"] >= 100
        for save in telemetry["saves"] for axis in save["axes"]
    )
    assert qualifying_axis or artist_axis, (
        "The script did not create two overlaid 50-bin histograms with alpha=0.5."
    )

    legends = [
        [label.strip() for label in axis["legend_labels"] if label.strip()]
        for save in telemetry["saves"] for axis in save["axes"]
    ]
    assert any(len(set(labels)) >= 2 for labels in legends), (
        "The overlaid distributions must have distinct, visible legend labels."
    )


def execute_and_check(single, multi):
    for path in (TXT, PNG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    fd, telemetry_path = tempfile.mkstemp(prefix="analyze-telemetry-", suffix=".json")
    os.close(fd)
    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    env["ANALYZE_TELEMETRY"] = telemetry_path
    try:
        result = subprocess.run(
            ["python3", "/tmp/run_analyze_instrumented.py"],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, (
            "analyze_sim.py did not execute successfully.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(TXT), f"Missing output file: {TXT}"
        with open(TXT, "r", encoding="utf-8") as f:
            actual = f.read().strip()
        expected = f"{expected_distance(single, multi):.4f}"
        assert actual == expected, f"Expected Wasserstein distance '{expected}', found '{actual}'."
        assert_real_png(PNG)
        with open(telemetry_path, "r", encoding="utf-8") as f:
            telemetry = json.load(f)
        assert_histogram_telemetry(telemetry)
    finally:
        try:
            os.remove(telemetry_path)
        except FileNotFoundError:
            pass


def test_script_executes_reproducibly_and_builds_required_histogram():
    assert os.path.isfile(SCRIPT), f"The script {SCRIPT} does not exist."
    with open(SINGLE, "rb") as f:
        original_single_bytes = f.read()
    with open(MULTI, "rb") as f:
        original_multi_bytes = f.read()

    rng = np.random.default_rng()
    challenge_single = rng.normal(3.75, 1.4, 1000)
    challenge_multi = challenge_single + rng.normal(0.031, 0.17, 1000)

    try:
        np.savetxt(SINGLE, challenge_single, fmt="%.12f")
        np.savetxt(MULTI, challenge_multi, fmt="%.12f")
        # Re-read the rounded values actually supplied to the script.
        challenge_single = np.loadtxt(SINGLE)
        challenge_multi = np.loadtxt(MULTI)
        execute_and_check(challenge_single, challenge_multi)
    finally:
        with open(SINGLE, "wb") as f:
            f.write(original_single_bytes)
        with open(MULTI, "wb") as f:
            f.write(original_multi_bytes)

    # Leave the required outputs regenerated from the original task inputs.
    execute_and_check(np.loadtxt(SINGLE), np.loadtxt(MULTI))


def test_analyze_sim_script_exists():
    """Test that the analysis script exists."""
    script_file = "/home/user/analyze_sim.py"
    assert os.path.isfile(script_file), f"The script {script_file} does not exist."


def test_distributions_png_exists():
    """Test that the distributions plot exists and is a valid PNG file."""
    png_path = "/home/user/distributions.png"
    assert os.path.isfile(png_path), f"The plot {png_path} does not exist."
    with open(png_path, "rb") as f:
        header = f.read(8)
    assert header == b"\x89PNG\r\n\x1a\n", f"The file {png_path} is not a valid PNG image."
    assert_real_png(png_path)


def test_wasserstein_txt():
    """Test that the wasserstein distance output is correct."""
    single_path = "/home/user/single_thread.csv"
    multi_path = "/home/user/multi_thread.csv"
    txt_path = "/home/user/wasserstein.txt"

    assert os.path.isfile(single_path), f"Missing input file: {single_path}"
    assert os.path.isfile(multi_path), f"Missing input file: {multi_path}"
    assert os.path.isfile(txt_path), f"Missing output file: {txt_path}"

    with open(single_path, "r") as f:
        single = [float(line.strip()) for line in f if line.strip()]
    with open(multi_path, "r") as f:
        multi = [float(line.strip()) for line in f if line.strip()]

    assert len(single) == len(multi), "Data files have different number of lines."
    assert len(single) > 0, "Data files are empty."

    single.sort()
    multi.sort()
    dist = sum(abs(s - m) for s, m in zip(single, multi)) / len(single)
    expected_str = f"{dist:.4f}"

    with open(txt_path, "r") as f:
        actual_str = f.read().strip()

    assert actual_str == expected_str, (
        f"Incorrect Wasserstein distance in {txt_path}. "
        f"Expected: '{expected_str}', Found: '{actual_str}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
