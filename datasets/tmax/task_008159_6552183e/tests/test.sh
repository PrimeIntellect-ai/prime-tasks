#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
from scipy.integrate import odeint
from scipy.optimize import curve_fit

CI_PATH = '/home/user/ci.txt'
PLOT_PATH = '/home/user/fit_plot.png'
DATA_PATH = '/home/user/decay_data.csv'


def parse_ci(path=CI_PATH):
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, 'r') as f:
        content = f.read().strip().split('\n')

    assert len(content) >= 2, f"Expected at least 2 lines in {path}, got {len(content)}."
    k_line = content[0].strip()
    c_line = content[1].strip()

    k_match = re.match(r'^k:\s*\[(-?\d+\.\d{3}),\s*(-?\d+\.\d{3})\]$', k_line)
    assert k_match is not None, f"Line 1 format incorrect. Expected 'k: [lower, upper]' with 3 decimal places, got: '{k_line}'"
    c_match = re.match(r'^c:\s*\[(-?\d+\.\d{3}),\s*(-?\d+\.\d{3})\]$', c_line)
    assert c_match is not None, f"Line 2 format incorrect. Expected 'c: [lower, upper]' with 3 decimal places, got: '{c_line}'"

    values = np.array([
        float(k_match.group(1)), float(k_match.group(2)),
        float(c_match.group(1)), float(c_match.group(2)),
    ])
    assert values[0] < values[1], "k lower bound must be less than upper bound"
    assert values[2] < values[3], "c lower bound must be less than upper bound"
    return values


def reference_ci(frame):
    t = frame['time'].to_numpy(dtype=float)
    y = frame['y'].to_numpy(dtype=float)

    def model(times, k, c):
        def rhs(state, time, kk, cc):
            return -kk * state - cc * state**2
        return odeint(rhs, 10.0, times, args=(k, c)).ravel()

    best, _ = curve_fit(model, t, y, p0=[0.1, 0.1], maxfev=100000)
    fitted = model(t, *best)
    residuals = y - fitted

    boot = []
    np.random.seed(123)
    for _ in range(200):
        sampled = np.random.choice(residuals, size=len(residuals), replace=True)
        synthetic = fitted + sampled
        params, _ = curve_fit(model, t, synthetic, p0=best, maxfev=100000)
        boot.append(params)

    boot = np.asarray(boot)
    return np.array([
        np.percentile(boot[:, 0], 2.5),
        np.percentile(boot[:, 0], 97.5),
        np.percentile(boot[:, 1], 2.5),
        np.percentile(boot[:, 1], 97.5),
    ])


def validate_plot():
    assert os.path.isfile(PLOT_PATH), f"Plot file {PLOT_PATH} is missing."
    assert os.path.getsize(PLOT_PATH) > 0, f"Plot file {PLOT_PATH} is empty."
    with open(PLOT_PATH, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', "fit_plot.png is not a PNG image"
    image = np.asarray(mpimg.imread(PLOT_PATH), dtype=float)
    assert image.ndim in (2, 3), "Plot is not a valid raster image"
    assert image.shape[0] >= 200 and image.shape[1] >= 300, "Plot dimensions are too small"
    assert np.isfinite(image).all(), "Plot contains invalid pixels"
    assert float(np.std(image)) > 0.01, "Plot appears blank or visually trivial"
    rgb = image[..., :3] if image.ndim == 3 else image
    assert float(np.mean(rgb < 0.95)) > 0.005, "Plot does not contain enough rendered data"


def candidate_scripts():
    found = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for name in files:
            if not name.endswith('.py'):
                continue
            path = os.path.join(root, name)
            try:
                source = open(path, 'r', errors='ignore').read()
            except OSError:
                continue
            if 'decay_data.csv' in source and 'ci.txt' in source and 'fit_plot.png' in source:
                found.append(path)
    return found


def run_script(path):
    env = os.environ.copy()
    env['MPLBACKEND'] = 'Agg'
    return subprocess.run(
        ['python3', path], cwd=os.path.dirname(path) or '/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=300
    )


def assert_ci_matches(expected):
    actual = parse_ci()
    # Allow minor numerical-solver differences while still requiring the
    # independently derived, seeded bootstrap result.
    assert np.allclose(actual, expected, atol=0.02, rtol=0), \
        f"Confidence intervals are incorrect: got {actual}, expected approximately {expected}"


def test_script_executes_and_recomputes_results():
    scripts = candidate_scripts()
    assert scripts, "No Python analysis script producing ci.txt and fit_plot.png was found."

    original_bytes = open(DATA_PATH, 'rb').read()
    original_frame = pd.read_csv(DATA_PATH)

    rng = np.random.RandomState(917)
    hidden_t = np.linspace(0.0, 4.5, 27)

    def rhs(state, time):
        return -0.38 * state - 0.16 * state**2

    hidden_y = odeint(rhs, 10.0, hidden_t).ravel() + rng.normal(0.0, 0.30, len(hidden_t))
    hidden_frame = pd.DataFrame({'time': hidden_t, 'y': hidden_y})
    hidden_expected = reference_ci(hidden_frame)
    original_expected = reference_ci(original_frame)
    passing_script = None
    failures = []

    try:
        hidden_frame.to_csv(DATA_PATH, index=False)
        for script in scripts:
            for output in (CI_PATH, PLOT_PATH):
                if os.path.exists(output):
                    os.remove(output)
            try:
                result = run_script(script)
                if result.returncode != 0:
                    failures.append(f"{script}: exited {result.returncode}: {result.stderr[-500:]}")
                    continue
                assert_ci_matches(hidden_expected)
                validate_plot()
                passing_script = script
                break
            except Exception as exc:
                failures.append(f"{script}: {exc}")

        assert passing_script is not None, "No submitted script correctly handled unseen decay data. " + " | ".join(failures)

        with open(DATA_PATH, 'wb') as f:
            f.write(original_bytes)
        for output in (CI_PATH, PLOT_PATH):
            if os.path.exists(output):
                os.remove(output)
        result = run_script(passing_script)
        assert result.returncode == 0, f"Analysis script failed on the supplied data: {result.stderr[-1000:]}"
        assert_ci_matches(original_expected)
        validate_plot()
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_bytes)


def test_ci_file_exists_and_format():
    ci_path = '/home/user/ci.txt'
    assert os.path.isfile(ci_path), f"File {ci_path} is missing."

    with open(ci_path, 'r') as f:
        content = f.read().strip().split('\n')

    assert len(content) >= 2, f"Expected at least 2 lines in {ci_path}, got {len(content)}."

    k_line = content[0].strip()
    c_line = content[1].strip()

    k_match = re.match(r'^k:\s*\[(-?\d+\.\d{3}),\s*(-?\d+\.\d{3})\]$', k_line)
    assert k_match is not None, f"Line 1 format incorrect. Expected 'k: [lower, upper]' with 3 decimal places, got: '{k_line}'"

    c_match = re.match(r'^c:\s*\[(-?\d+\.\d{3}),\s*(-?\d+\.\d{3})\]$', c_line)
    assert c_match is not None, f"Line 2 format incorrect. Expected 'c: [lower, upper]' with 3 decimal places, got: '{c_line}'"

    k_lower, k_upper = float(k_match.group(1)), float(k_match.group(2))
    c_lower, c_upper = float(c_match.group(1)), float(c_match.group(2))

    assert k_lower < k_upper, "k lower bound must be less than upper bound"
    assert c_lower < c_upper, "c lower bound must be less than upper bound"


def test_plot_file_exists():
    plot_path = '/home/user/fit_plot.png'
    assert os.path.isfile(plot_path), f"Plot file {plot_path} is missing."
    assert os.path.getsize(plot_path) > 0, f"Plot file {plot_path} is empty."
    validate_plot()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
