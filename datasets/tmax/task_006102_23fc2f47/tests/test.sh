#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import subprocess

import numpy as np
from scipy.integrate import solve_ivp

SCRIPT_PATH = "/home/user/generate_ode_data.py"
JSON_PATH = "/home/user/stability_report.json"
CSV_PATH = "/home/user/training_data.csv"


def test_script_exists_and_executes():
    assert os.path.isfile(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist or is not a regular file."

    # Require the submitted script itself to regenerate both artifacts.
    for path in (JSON_PATH, CSV_PATH):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(JSON_PATH), f"Script did not create {JSON_PATH}."
    assert os.path.exists(CSV_PATH), f"Script did not create {CSV_PATH}."


def _expected_mse_values():
    t_eval = np.linspace(0, 1, 100)

    def ode_system(t, y):
        return [-1000 * y[0] + y[1], -y[1]]

    analytical = np.vstack((
        (998 / 999) * np.exp(-1000 * t_eval) + (1 / 999) * np.exp(-t_eval),
        np.exp(-t_eval),
    ))

    rk45 = solve_ivp(
        ode_system, (0, 1), [1.0, 1.0], method="RK45", t_eval=t_eval
    )
    bdf = solve_ivp(
        ode_system, (0, 1), [1.0, 1.0], method="BDF", t_eval=t_eval
    )

    assert rk45.success, f"Verifier RK45 solve failed: {rk45.message}"
    assert bdf.success, f"Verifier BDF solve failed: {bdf.message}"

    return (
        float(np.mean((rk45.y - analytical) ** 2)),
        float(np.mean((bdf.y - analytical) ** 2)),
    )


def test_stability_report_json():
    json_path = JSON_PATH
    assert os.path.exists(json_path), f"File {json_path} does not exist."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} is not a valid JSON file."

    assert "mse_rk45" in data, "Key 'mse_rk45' missing in stability_report.json"
    assert "mse_bdf" in data, "Key 'mse_bdf' missing in stability_report.json"
    assert set(data) == {"mse_rk45", "mse_bdf"}, \
        "stability_report.json must contain exactly the required keys"

    assert isinstance(data["mse_rk45"], (int, float)), "'mse_rk45' must be a float"
    assert isinstance(data["mse_bdf"], (int, float)), "'mse_bdf' must be a float"

    assert data["mse_rk45"] > 0, "'mse_rk45' must be greater than 0"
    assert data["mse_bdf"] > 0, "'mse_bdf' must be greater than 0"
    assert math.isfinite(data["mse_rk45"]), "'mse_rk45' must be finite"
    assert math.isfinite(data["mse_bdf"]), "'mse_bdf' must be finite"

    expected_rk45, expected_bdf = _expected_mse_values()
    assert math.isclose(
        data["mse_rk45"], expected_rk45, rel_tol=1e-6, abs_tol=1e-18
    ), f"Incorrect RK45 MSE: expected {expected_rk45}, got {data['mse_rk45']}"
    assert math.isclose(
        data["mse_bdf"], expected_bdf, rel_tol=1e-6, abs_tol=1e-18
    ), f"Incorrect BDF MSE: expected {expected_bdf}, got {data['mse_bdf']}"


def test_training_data_csv():
    csv_path = CSV_PATH
    assert os.path.exists(csv_path), f"File {csv_path} does not exist."

    with open(csv_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 101, f"Expected 101 lines in {csv_path}, found {len(lines)}"
    assert lines[0] == "t,y1,y2", f"Expected header 't,y1,y2', found '{lines[0]}'"

    # Calculate truth
    for i in range(100):
        t = i / 99.0
        y1 = (998/999) * math.exp(-1000 * t) + (1/999) * math.exp(-t)
        y2 = math.exp(-t)

        expected_line = f"{round(t, 6):.6f},{round(y1, 6):.6f},{round(y2, 6):.6f}"
        # pandas round might strip trailing zeros, so let's parse floats to compare
        actual_parts = lines[i+1].split(',')
        assert len(actual_parts) == 3, f"Line {i+2} does not have 3 columns"

        actual_t, actual_y1, actual_y2 = map(float, actual_parts)

        assert math.isclose(actual_t, round(t, 6), rel_tol=1e-6, abs_tol=1e-6), \
            f"Row {i+1}: expected t={round(t, 6)}, got {actual_t}"
        assert math.isclose(actual_y1, round(y1, 6), rel_tol=1e-6, abs_tol=1e-6), \
            f"Row {i+1}: expected y1={round(y1, 6)}, got {actual_y1}"
        assert math.isclose(actual_y2, round(y2, 6), rel_tol=1e-6, abs_tol=1e-6), \
            f"Row {i+1}: expected y2={round(y2, 6)}, got {actual_y2}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
