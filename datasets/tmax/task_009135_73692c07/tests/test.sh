#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import pytest

SCRIPT_PATH = "/home/user/run_study.sh"
LOG_PATH = "/home/user/study_results.log"


def test_script_exists_executable_and_runs():
    """Verify the required script exists, is executable, and generates a fresh log."""
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable."

    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    try:
        result = subprocess.run(
            [SCRIPT_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{SCRIPT_PATH} timed out.")

    assert result.returncode == 0, (
        f"{SCRIPT_PATH} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_log_file_exists():
    """Verify that executing the script created the output log file."""
    assert os.path.isfile(LOG_PATH), f"{LOG_PATH} does not exist after running the script."


def test_results_correctness():
    """Verify the fresh study log against independently simulated values."""
    if not os.path.isfile(LOG_PATH):
        pytest.fail("Log file missing.")

    with open(LOG_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in the log file, found {len(lines)}."

    alpha = 0.1
    expected_Ns = [10, 20, 40]
    expected_data = {}

    for N in expected_Ns:
        dx = 1.0 / N
        dt_max = (dx ** 2) / (2 * alpha)
        dt_stable = 0.9 * dt_max
        dt_unstable = 1.1 * dt_max

        M_stable = math.ceil(0.5 / dt_stable)
        t_end_stable = M_stable * dt_stable

        u_stable = [math.sin(math.pi * i * dx) for i in range(N + 1)]
        for _ in range(M_stable):
            u_new = list(u_stable)
            for i in range(1, N):
                u_new[i] = u_stable[i] + (alpha * dt_stable / dx ** 2) * (
                    u_stable[i + 1] - 2 * u_stable[i] + u_stable[i - 1]
                )
            u_stable = u_new

        mae_stable = 0.0
        for i in range(1, N):
            x = i * dx
            exact = math.sin(math.pi * x) * math.exp(-math.pi ** 2 * alpha * t_end_stable)
            mae_stable += abs(u_stable[i] - exact)
        mae_stable /= N - 1

        M_unstable = math.ceil(0.5 / dt_unstable)
        u_unstable = [math.sin(math.pi * i * dx) for i in range(N + 1)]
        for _ in range(M_unstable):
            u_new = list(u_unstable)
            for i in range(1, N):
                u_new[i] = u_unstable[i] + (alpha * dt_unstable / dx ** 2) * (
                    u_unstable[i + 1] - 2 * u_unstable[i] + u_unstable[i - 1]
                )
            u_unstable = u_new
        max_abs_unstable = max(abs(value) for value in u_unstable)

        expected_data[N] = {
            "dt_stable": dt_stable,
            "mae_stable": mae_stable,
            "dt_unstable": dt_unstable,
            "max_abs_unstable": max_abs_unstable,
        }

    float_field = re.compile(r"^-?\d+\.\d{6}$")

    for idx, line in enumerate(lines):
        parts = line.split(",")
        assert len(parts) == 5, (
            f"Line {idx + 1} does not have exactly 5 comma-separated values: {line}"
        )
        assert all(float_field.fullmatch(field) for field in parts[1:]), (
            f"Line {idx + 1} floating-point fields must have exactly 6 decimal places: {line}"
        )

        try:
            N_val = int(parts[0])
            dt_stable_val = float(parts[1])
            mae_stable_val = float(parts[2])
            dt_unstable_val = float(parts[3])
            max_abs_unstable_val = float(parts[4])
        except ValueError:
            pytest.fail(f"Could not parse numerical values from line {idx + 1}: {line}")

        assert N_val == expected_Ns[idx], (
            f"Expected N={expected_Ns[idx]} on line {idx + 1}, got {N_val}"
        )
        exp = expected_data[N_val]

        assert math.isclose(dt_stable_val, exp["dt_stable"], abs_tol=1e-5), (
            f"For N={N_val}, expected dt_stable ~ {exp['dt_stable']:.6f}, got {dt_stable_val}"
        )
        assert math.isclose(dt_unstable_val, exp["dt_unstable"], abs_tol=1e-5), (
            f"For N={N_val}, expected dt_unstable ~ {exp['dt_unstable']:.6f}, got {dt_unstable_val}"
        )
        assert math.isclose(mae_stable_val, exp["mae_stable"], abs_tol=1e-4), (
            f"For N={N_val}, expected MAE_stable ~ {exp['mae_stable']:.6f}, got {mae_stable_val}"
        )
        assert math.isclose(
            max_abs_unstable_val, exp["max_abs_unstable"], abs_tol=1e-4
        ), (
            f"For N={N_val}, expected max_abs_unstable ~ "
            f"{exp['max_abs_unstable']:.6f}, got {max_abs_unstable_val}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
