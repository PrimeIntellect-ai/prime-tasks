#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess

import pytest


@pytest.fixture(scope="session", autouse=True)
def run_submission():
    script_path = "/home/user/profile_regression.py"
    report_path = "/home/user/report.json"

    assert os.path.isfile(script_path), f"Expected Python script at {script_path} was not found."

    if os.path.exists(report_path):
        os.remove(report_path)

    try:
        result = subprocess.run(
            ["python3", script_path],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("profile_regression.py timed out while executing.")

    assert result.returncode == 0, (
        "profile_regression.py failed to execute successfully.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def test_report_exists_and_valid():
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"Expected report file at {report_path} was not found."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file report.json is not valid JSON.")

    required_keys = {"max_abs_error_x", "ci_lower", "ci_upper"}
    missing_keys = required_keys - set(data.keys())
    assert not missing_keys, f"report.json is missing required keys: {missing_keys}"

    for key in required_keys:
        assert isinstance(data[key], (int, float)), f"Value for {key} must be a number."


def test_report_values():
    try:
        import numpy as np
        from scipy.integrate import solve_ivp
    except ImportError:
        pytest.fail("Required libraries (numpy, scipy) are not installed in the environment.")

    def lv(t, z, alpha, beta, delta, gamma):
        x, y = z
        return [alpha*x - beta*x*y, delta*x*y - gamma*y]

    t_eval = np.linspace(0, 10, 200)

    baseline = np.genfromtxt("/home/user/baseline.csv", delimiter=",", names=True)
    assert len(baseline) == 200, "baseline.csv must contain 200 data rows."
    baseline_sol = solve_ivp(
        lv,
        [0, 10],
        [10.0, 5.0],
        args=(1.5, 1.0, 1.0, 3.0),
        t_eval=t_eval,
    )
    expected_max_abs_error_x = float(
        np.max(np.abs(baseline_sol.y[0] - baseline["x"]))
    )

    max_xs = []
    for i in range(200):
        alpha = 1.5 + 0.1 * np.sin(i)
        sol = solve_ivp(lv, [0, 10], [10.0, 5.0], args=(alpha, 1.0, 1.0, 3.0), t_eval=t_eval)
        max_xs.append(np.max(sol.y[0]))

    max_xs = np.array(max_xs)
    np.random.seed(42)
    boot_means = []
    for _ in range(1000):
        resample = np.random.choice(max_xs, size=200, replace=True)
        boot_means.append(np.mean(resample))

    expected_ci_lower = float(np.percentile(boot_means, 2.5))
    expected_ci_upper = float(np.percentile(boot_means, 97.5))

    with open("/home/user/report.json", "r") as f:
        ans = json.load(f)

    max_abs_error_x = ans["max_abs_error_x"]
    ci_lower = ans["ci_lower"]
    ci_upper = ans["ci_upper"]

    assert max_abs_error_x < 1e-5, f"max_abs_error_x is too high: {max_abs_error_x}. Expected < 1e-5."

    error_diff = abs(max_abs_error_x - expected_max_abs_error_x)
    assert error_diff < 1e-10, (
        f"max_abs_error_x is incorrect. Expected {expected_max_abs_error_x}, "
        f"got {max_abs_error_x}."
    )

    lower_diff = abs(ci_lower - expected_ci_lower)
    assert lower_diff < 1e-5, f"ci_lower is incorrect. Expected {expected_ci_lower}, got {ci_lower}."

    upper_diff = abs(ci_upper - expected_ci_upper)
    assert upper_diff < 1e-5, f"ci_upper is incorrect. Expected {expected_ci_upper}, got {ci_upper}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
