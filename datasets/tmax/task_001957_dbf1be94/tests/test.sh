#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
from functools import lru_cache

import matplotlib.image as mpimg
import numpy as np
import pytest
from scipy.integrate import simpson

HISTOGRAM = "/home/user/response_histogram.png"
RESULTS = "/home/user/simulation_results.json"


@lru_cache(maxsize=1)
def expected_statistics():
    """Independently reproduce the simulation specified in the instruction."""
    np.random.seed(42)
    b = np.ones(50)
    t = np.linspace(0.0, 1.0, 50)
    responses = []

    for _ in range(500):
        X = np.random.normal(0.0, 1.0, (50, 50))
        A = X @ X.T + 0.1 * np.eye(50)
        L = np.linalg.cholesky(A)
        z = np.linalg.solve(L, b)
        y = np.linalg.solve(L.T, z)
        responses.append(float(simpson(y, x=t)))

    values = np.asarray(responses)
    return float(np.mean(values)), float(np.std(values))


def candidate_scripts():
    roots = ["/home/user", "/workspace", "/app", "/root", "/tmp"]
    found = []
    verifier_file = os.path.realpath(__file__)

    for root in roots:
        if not os.path.isdir(root):
            continue
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if not d.startswith(".") and d != "__pycache__"]
            for name in files:
                if not name.endswith(".py"):
                    continue
                path = os.path.realpath(os.path.join(current, name))
                if path == verifier_file or path.startswith("/tmp/test_final_state"):
                    continue
                try:
                    if os.path.getsize(path) <= 1_000_000:
                        found.append(path)
                except OSError:
                    pass

    return sorted(set(found), key=lambda p: os.path.getmtime(p), reverse=True)


def outputs_match_reference():
    if not os.path.isfile(HISTOGRAM) or os.path.getsize(HISTOGRAM) == 0:
        return False
    if not os.path.isfile(RESULTS):
        return False
    try:
        with open(RESULTS, "r") as f:
            data = json.load(f)
        mean_R = data["mean_R"]
        std_R = data["std_R"]
        if isinstance(mean_R, bool) or isinstance(std_R, bool):
            return False
        if not isinstance(mean_R, (int, float)) or not isinstance(std_R, (int, float)):
            return False
        expected_mean, expected_std = expected_statistics()
        return (math.isclose(mean_R, expected_mean, abs_tol=1e-4) and
                math.isclose(std_R, expected_std, abs_tol=1e-4))
    except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
        return False


@pytest.fixture(scope="session", autouse=True)
def execute_submission_script():
    """Delete precomputed artifacts and require a submitted Python script to recreate them."""
    scripts = candidate_scripts()
    assert scripts, "No submitted Python simulation script was found."

    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    attempts = []

    for script in scripts:
        for output in (HISTOGRAM, RESULTS):
            try:
                os.remove(output)
            except FileNotFoundError:
                pass

        try:
            completed = subprocess.run(
                ["python3", script],
                cwd=os.path.dirname(script) or "/home/user",
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=180,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            attempts.append(f"{script}: {exc}")
            continue

        if completed.returncode == 0 and outputs_match_reference():
            return
        attempts.append(f"{script}: exit status {completed.returncode}")

    pytest.fail("No submitted Python script recreated correct simulation artifacts. " + "; ".join(attempts[:5]))


def test_histogram_exists():
    """Verify that the histogram image was created and is a genuine nontrivial image."""
    file_path = HISTOGRAM
    assert os.path.isfile(file_path), f"File not found: {file_path}"
    assert os.path.getsize(file_path) > 0, f"File is empty: {file_path}"

    try:
        image = mpimg.imread(file_path)
    except Exception as exc:
        pytest.fail(f"File {file_path} is not a readable image: {exc}")
    assert image.ndim in (2, 3), "Histogram has invalid image dimensions."
    assert image.shape[0] >= 100 and image.shape[1] >= 100, "Histogram image is implausibly small."
    assert np.ptp(np.asarray(image, dtype=float)) > 0.05, "Histogram image has no meaningful visual content."


def test_simulation_results_json():
    """Verify the JSON file contains statistics from the instructed deterministic simulation."""
    file_path = RESULTS
    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    assert "mean_R" in data, "Key 'mean_R' missing from JSON."
    assert "std_R" in data, "Key 'std_R' missing from JSON."
    assert set(data) == {"mean_R", "std_R"}, "JSON must contain exactly the specified keys."

    expected_mean_R, expected_std_R = expected_statistics()
    mean_R = data["mean_R"]
    std_R = data["std_R"]

    assert isinstance(mean_R, (int, float)) and not isinstance(mean_R, bool), "'mean_R' must be a number."
    assert isinstance(std_R, (int, float)) and not isinstance(std_R, bool), "'std_R' must be a number."

    assert math.isclose(mean_R, expected_mean_R, abs_tol=1e-4), \
        f"Expected mean_R ~ {expected_mean_R}, got {mean_R}"
    assert math.isclose(std_R, expected_std_R, abs_tol=1e-4), \
        f"Expected std_R ~ {expected_std_R}, got {std_R}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
