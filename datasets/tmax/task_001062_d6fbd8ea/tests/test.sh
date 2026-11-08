#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import stat

import cv2
import numpy as np
import pytest
from scipy.optimize import least_squares

RESULTS_PATH = "/home/user/results.json"
ANALYSIS_PATH = "/home/user/analysis.py"
VIDEO_PATH = "/app/experiment.mp4"
REQUIRED_KEYS = [
    "gamma",
    "omega",
    "noise_variance_ci_lower",
    "noise_variance_ci_upper",
]


def load_results():
    with open(RESULTS_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON in {RESULTS_PATH}: {e}")


def test_analysis_script_exists_and_contains_workflow():
    assert os.path.exists(ANALYSIS_PATH), f"The analysis script {ANALYSIS_PATH} does not exist."
    assert os.path.isfile(ANALYSIS_PATH), f"The path {ANALYSIS_PATH} is not a file."
    mode = os.stat(ANALYSIS_PATH).st_mode
    assert stat.S_ISREG(mode), f"The path {ANALYSIS_PATH} must be a regular file."

    with open(ANALYSIS_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    assert source.strip(), "analysis.py is empty."

    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        pytest.fail(f"analysis.py is not valid Python: {e}")

    names = set()
    strings = []
    integer_values = set()

    def constant_integer(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, int) and not isinstance(node.value, bool):
            return node.value
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
            value = constant_integer(node.operand)
            if value is not None:
                return value if isinstance(node.op, ast.UAdd) else -value
        if isinstance(node, ast.BinOp):
            left = constant_integer(node.left)
            right = constant_integer(node.right)
            if left is None or right is None:
                return None
            try:
                if isinstance(node.op, ast.Add): return left + right
                if isinstance(node.op, ast.Sub): return left - right
                if isinstance(node.op, ast.Mult): return left * right
                if isinstance(node.op, ast.Pow): return left ** right
            except Exception:
                return None
        return None

    for node in ast.walk(tree):
        if isinstance(node, ast.Name):
            names.add(node.id.lower())
        elif isinstance(node, ast.Attribute):
            names.add(node.attr.lower())
        elif isinstance(node, ast.Constant):
            if isinstance(node.value, str):
                strings.append(node.value)
        value = constant_integer(node)
        if value is not None:
            integer_values.add(value)

    assert any("experiment.mp4" in s and "/app" in s for s in strings), \
        "analysis.py must read /app/experiment.mp4."
    assert "videocapture" in names, \
        "analysis.py must open and process the experiment video with cv2.VideoCapture."

    has_mcmc_api = bool({"ensemblesampler", "run_mcmc", "mcmc", "metropolis"} & names)
    has_custom_mcmc = (
        bool({"log_probability", "log_posterior", "log_likelihood", "lnprob", "lnlike"} & names)
        and bool({"random", "uniform", "normal", "rand", "randn"} & names)
        and any(isinstance(n, (ast.For, ast.While)) for n in ast.walk(tree))
    )
    assert has_mcmc_api or has_custom_mcmc, \
        "analysis.py must actually implement or invoke MCMC sampling."

    assert any("resid" in name for name in names), \
        "analysis.py must calculate residual errors."
    assert any("bootstrap" in name for name in names), \
        "analysis.py must perform residual bootstrap processing."
    assert bool({"choice", "resample"} & names), \
        "Bootstrap residuals must be sampled with replacement."
    assert bool({"percentile", "quantile"} & names), \
        "Bootstrap confidence limits must be calculated from bootstrap quantiles."
    assert 1000 in integer_values, \
        "analysis.py must specify the required 1000 bootstrap iterations."


def test_results_file_exists():
    assert os.path.exists(RESULTS_PATH), f"The results file {RESULTS_PATH} does not exist."
    assert os.path.isfile(RESULTS_PATH), f"The path {RESULTS_PATH} is not a file."


def test_results_keys():
    data = load_results()
    for k in REQUIRED_KEYS:
        assert k in data, f"Missing required key '{k}' in {RESULTS_PATH}."
        assert isinstance(data[k], (int, float)), f"Key '{k}' must be a float."
        assert not isinstance(data[k], bool), f"Key '{k}' must be a float."
        assert math.isfinite(float(data[k])), f"Key '{k}' must be finite."
    assert set(data) == set(REQUIRED_KEYS), \
        f"{RESULTS_PATH} must contain exactly the four required keys."


def test_parameter_accuracy():
    data = load_results()

    true_gamma = 0.2
    true_omega = 3.14159

    gamma = data["gamma"]
    omega = data["omega"]

    err_gamma = abs(gamma - true_gamma)
    err_omega = abs(omega - true_omega)

    max_err = max(err_gamma, err_omega)

    assert max_err <= 0.05, (
        f"Parameter estimates exceed the tolerance threshold of 0.05. "
        f"Gamma error: {err_gamma:.4f} (estimated {gamma}, true {true_gamma}), "
        f"Omega error: {err_omega:.4f} (estimated {omega}, true {true_omega}), "
        f"Max error: {max_err:.4f}"
    )


def independently_extract_positions():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Verifier could not open {VIDEO_PATH}."
    xs = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        _, mask = cv2.threshold(gray, 180, 255, cv2.THRESH_BINARY)
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        assert contours, "A video frame did not contain a detectable bright object."
        contour = max(contours, key=cv2.contourArea)
        moments = cv2.moments(contour)
        assert moments["m00"] > 0
        xs.append(moments["m10"] / moments["m00"])
    cap.release()
    assert len(xs) == 300, f"Expected 300 video frames, found {len(xs)}."
    return np.asarray(xs, dtype=float)


def reference_bootstrap_ci(gamma, omega):
    x = independently_extract_positions()
    t = np.arange(x.size, dtype=float) / 30.0

    # For the submitted gamma and omega, independently estimate the remaining
    # sinusoid coefficients and baseline. This is the same oscillator model,
    # expressed linearly as C*cos(omega*t)+D*sin(omega*t).
    design = np.column_stack((
        np.exp(-gamma * t) * np.cos(omega * t),
        np.exp(-gamma * t) * np.sin(omega * t),
        np.ones_like(t),
    ))
    coefficients, _, _, _ = np.linalg.lstsq(design, x, rcond=None)
    residuals = x - design @ coefficients

    rng = np.random.default_rng(731942)
    variances = np.empty(20000, dtype=float)
    for start in range(0, variances.size, 500):
        count = min(500, variances.size - start)
        indices = rng.integers(0, residuals.size, size=(count, residuals.size))
        variances[start:start + count] = np.var(residuals[indices], axis=1)
    return np.percentile(variances, [2.5, 97.5])


def test_bootstrap_confidence_interval_matches_video_residuals():
    data = load_results()
    lower = float(data["noise_variance_ci_lower"])
    upper = float(data["noise_variance_ci_upper"])
    assert 0 <= lower < upper, "Noise variance CI must be ordered and non-negative."

    expected_lower, expected_upper = reference_bootstrap_ci(
        float(data["gamma"]), float(data["omega"])
    )
    lower_tolerance = max(0.75, 0.20 * abs(expected_lower))
    upper_tolerance = max(0.75, 0.20 * abs(expected_upper))
    assert abs(lower - expected_lower) <= lower_tolerance, (
        f"Reported lower noise-variance CI bound {lower} is inconsistent with "
        f"the video residuals (independent estimate {expected_lower:.4f})."
    )
    assert abs(upper - expected_upper) <= upper_tolerance, (
        f"Reported upper noise-variance CI bound {upper} is inconsistent with "
        f"the video residuals (independent estimate {expected_upper:.4f})."
    )
TEST_EOF

rm -f /home/user/results.json
if (cd /home/user && timeout 600s python3 /home/user/analysis.py) \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
