#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess

import numpy as np
from scipy.optimize import minimize
from scipy.stats import gaussian_kde

SCRIPT_PATH = "/home/user/profiler.sh"
RESULTS_PATH = "/home/user/results.json"


def reference_values():
    """Independently execute the instructed numerical pipeline."""
    np.random.seed(42)
    latencies = np.random.normal(100.0, 15.0, 10000)

    kde_110 = float(gaussian_kde(latencies)([110.0])[0])

    matrix = latencies[:100].reshape((10, 10))
    spd = matrix.T @ matrix + np.eye(10)
    lower = np.linalg.cholesky(spd)
    cholesky_norm = float(np.linalg.norm(lower, ord="fro"))

    empirical_mean = float(np.mean(latencies))
    result = minimize(
        lambda x: (x[0] - empirical_mean) ** 2 + 0.5 * x[0],
        np.array([100.0]),
    )
    assert result.success, f"Reference optimization failed: {result.message}"
    optimal_x = float(result.x[0])

    return {
        "kde_110": round(kde_110, 4),
        "cholesky_norm": round(cholesky_norm, 4),
        "optimal_x": round(optimal_x, 4),
    }


def test_profiler_script_exists_and_executable():
    """Verify that /home/user/profiler.sh exists and is an executable Bash script."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "r", errors="replace") as handle:
        first_line = handle.readline().rstrip("\n")
    assert re.match(r"^#!.*\bbash(?:\s|$)", first_line), \
        f"{SCRIPT_PATH} must have a Bash shebang."


def test_profiler_script_execution_and_output():
    """Run the script and validate its newly generated JSON against the pipeline."""
    expected_values = reference_values()

    # Enforce the instruction that final answers are computed rather than embedded.
    with open(SCRIPT_PATH, "r", errors="replace") as handle:
        script_source = handle.read()
    for key, value in expected_values.items():
        literal = f"{value:.4f}"
        assert literal not in script_source, \
            f"The final value for {key} appears hardcoded in {SCRIPT_PATH}."

    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    try:
        subprocess.run(
            [SCRIPT_PATH],
            check=True,
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired as exc:
        assert False, f"Execution of {SCRIPT_PATH} timed out: {exc}"
    except subprocess.CalledProcessError as exc:
        assert False, (
            f"Execution of {SCRIPT_PATH} failed with return code {exc.returncode}.\n"
            f"Stdout: {exc.stdout}\nStderr: {exc.stderr}"
        )

    assert os.path.exists(RESULTS_PATH), \
        f"The script did not create {RESULTS_PATH}."
    assert os.path.isfile(RESULTS_PATH), f"{RESULTS_PATH} is not a file."

    with open(RESULTS_PATH, "r") as handle:
        raw_json = handle.read()

    try:
        data = json.loads(raw_json)
    except json.JSONDecodeError as exc:
        assert False, f"{RESULTS_PATH} does not contain valid JSON: {exc}"

    expected_keys = {"kde_110", "cholesky_norm", "optimal_x"}
    assert isinstance(data, dict), f"{RESULTS_PATH} must contain a JSON object."
    assert set(data.keys()) == expected_keys, \
        f"JSON keys {set(data.keys())} do not match expected keys {expected_keys}."

    # Each JSON number must be written in fixed-point notation with four decimals.
    for key in expected_keys:
        matches = re.findall(
            rf'"{re.escape(key)}"\s*:\s*(-?\d+\.\d{{4}})(?=\s*[,}}])',
            raw_json,
        )
        assert len(matches) == 1, \
            f"Value for {key} must be a JSON number with exactly 4 decimal places."

    for key, expected_val in expected_values.items():
        val = data[key]
        assert isinstance(val, (int, float)) and not isinstance(val, bool), \
            f"Value for {key} is not a number."
        assert math.isfinite(val), f"Value for {key} must be finite."
        assert math.isclose(val, expected_val, rel_tol=1e-4, abs_tol=1e-4), \
            f"Value for {key} is {val}, expected approximately {expected_val}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
