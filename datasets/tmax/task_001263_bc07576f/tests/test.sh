#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import subprocess
import math


def test_venv_exists():
    venv_python = "/home/user/venv/bin/python"
    assert os.path.exists(venv_python), f"Virtual environment python not found at {venv_python}"


def test_matplotlib_installed_in_venv():
    script = r'''
import json
import os
import sys
import matplotlib

prefix = os.path.realpath(sys.prefix)
module_path = os.path.realpath(matplotlib.__file__)
assert prefix == os.path.realpath('/home/user/venv'), (prefix, module_path)
assert os.path.commonpath([prefix, module_path]) == prefix, (
    'matplotlib is not installed inside the requested virtual environment',
    prefix,
    module_path,
)
print(json.dumps({'version': matplotlib.__version__, 'path': module_path}))
'''
    try:
        out = subprocess.check_output(
            ["/home/user/venv/bin/python", "-c", script],
            text=True,
            stderr=subprocess.STDOUT,
        )
        info = json.loads(out)
    except subprocess.CalledProcessError as e:
        assert False, f"matplotlib is not installed in /home/user/venv: {e.output}"
    assert info["version"], "Could not determine the installed matplotlib version"


def test_plot_exists():
    plot_path = "/home/user/fit_plot.png"
    assert os.path.exists(plot_path), f"Plot {plot_path} does not exist"
    assert os.path.getsize(plot_path) > 0, f"Plot {plot_path} is empty"


def test_plot_is_a_rendered_matplotlib_visualization():
    plot_path = "/home/user/fit_plot.png"
    with open(plot_path, "rb") as f:
        raw = f.read()
    assert raw.startswith(b"\x89PNG\r\n\x1a\n"), "fit_plot.png is not a PNG file"
    assert b"Matplotlib" in raw, "fit_plot.png was not saved as a matplotlib figure"

    script = r'''
import json
import numpy as np
import matplotlib.image as mpimg
from scipy import ndimage

path = '/home/user/fit_plot.png'
img = mpimg.imread(path)
assert img.ndim in (2, 3), f'unexpected image shape: {img.shape}'
assert img.shape[0] >= 200 and img.shape[1] >= 300, f'plot is too small: {img.shape}'
assert np.isfinite(img).all(), 'plot contains invalid pixel values'

if img.ndim == 2:
    rgb = np.repeat(img[..., None], 3, axis=2).astype(float)
else:
    rgb = img[..., :3].astype(float)
    if img.shape[2] >= 4:
        alpha = img[..., 3:4].astype(float)
        rgb = rgb * alpha + (1.0 - alpha)
if rgb.max() > 1.5:
    rgb /= 255.0

h, w = rgb.shape[:2]
cy, cx = max(2, h // 20), max(2, w // 20)
corners = np.concatenate([
    rgb[:cy, :cx].reshape(-1, 3),
    rgb[:cy, -cx:].reshape(-1, 3),
    rgb[-cy:, :cx].reshape(-1, 3),
    rgb[-cy:, -cx:].reshape(-1, 3),
], axis=0)
background = np.median(corners, axis=0)

# Ignore titles, labels, ticks, and the outer axes. The remaining interior must
# contain substantial marks distributed like both a curve and scatter points.
y0, y1 = int(0.15 * h), int(0.85 * h)
x0, x1 = int(0.15 * w), int(0.90 * w)
core = rgb[y0:y1, x0:x1]
mask = np.max(np.abs(core - background), axis=2) > 0.04
ink = int(mask.sum())
assert ink >= max(200, int(mask.size * 0.001)), 'plot interior is blank or nearly blank'
assert ink <= int(mask.size * 0.70), 'plot does not have a recognizable plotting area'

x_bins = np.array_split(mask, 24, axis=1)
y_bins = np.array_split(mask, 12, axis=0)
occupied_x = sum(bool(part.any()) for part in x_bins)
occupied_y = sum(bool(part.any()) for part in y_bins)
assert occupied_x >= 18, 'no fitted curve spanning the plotted N range was detected'
assert occupied_y >= 5, 'plot marks do not span a meaningful error range'

labels, count = ndimage.label(mask, structure=np.ones((3, 3), dtype=int))
sizes = np.bincount(labels.ravel())[1:] if count else np.array([], dtype=int)
substantial_components = int(np.count_nonzero(sizes >= 4))
assert substantial_components >= 3, 'scatter-point structure was not detected in the plot interior'

print(json.dumps({
    'height': h,
    'width': w,
    'ink': ink,
    'occupied_x': occupied_x,
    'occupied_y': occupied_y,
    'components': substantial_components,
}))
'''
    try:
        subprocess.check_output(
            ["/home/user/venv/bin/python", "-c", script],
            text=True,
            stderr=subprocess.STDOUT,
        )
    except subprocess.CalledProcessError as e:
        assert False, f"fit_plot.png is not a substantive scatter-and-fit visualization: {e.output}"


def test_results_json():
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), f"{results_path} does not exist"

    with open(results_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{results_path} is not valid JSON"

    expected_keys = ["bootstrap_ci_lower", "bootstrap_ci_upper", "optimized_a", "optimized_b"]
    for key in expected_keys:
        assert key in results, f"Key '{key}' missing in results.json"
        assert isinstance(results[key], (float, int)), f"Value for '{key}' is not a number"

    # Compute expected values using the venv's python to ensure we use the same libraries
    script = """
import numpy as np
import pandas as pd
from scipy.stats import bootstrap
from scipy.optimize import minimize
import json

df = pd.read_csv('/home/user/discrepancies.csv')
N = df['N'].values
error = df['error'].values

res = bootstrap((error,), np.mean, method='percentile', n_resamples=10000, random_state=42)
ci_lower = float(res.confidence_interval.low)
ci_upper = float(res.confidence_interval.high)

def mse(params):
    a, b = params
    pred = a * (N ** b)
    return np.mean((error - pred) ** 2)

opt = minimize(mse, [1e-16, 1.0], method='Nelder-Mead')
opt_a, opt_b = float(opt.x[0]), float(opt.x[1])

print(json.dumps({
  "bootstrap_ci_lower": ci_lower,
  "bootstrap_ci_upper": ci_upper,
  "optimized_a": opt_a,
  "optimized_b": opt_b
}))
"""
    try:
        out = subprocess.check_output(
            ["/home/user/venv/bin/python", "-c", script],
            text=True,
            stderr=subprocess.STDOUT
        )
        expected = json.loads(out)
    except subprocess.CalledProcessError as e:
        assert False, f"Failed to run verification script using venv python. Did you install numpy, pandas, and scipy? Output: {e.output}"
    except Exception as e:
        assert False, f"Failed to compute expected values: {e}"

    for key in expected_keys:
        assert math.isclose(results[key], expected[key], rel_tol=1e-4), \
            f"Value for {key} does not match expected. Got {results[key]}, expected {expected[key]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
