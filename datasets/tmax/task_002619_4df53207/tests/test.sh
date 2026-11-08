#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import pytest

ODE_DIR = "/home/user/ode"
FAST_SIM = os.path.join(ODE_DIR, "fast_sim")
SIMULATOR_C = os.path.join(ODE_DIR, "simulator.c")
BASELINE = os.path.join(ODE_DIR, "baseline.py")


def run_checked(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, (
        f"Command failed with exit code {result.returncode}: {cmd}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result.stdout


def parse_csv_output(output, description):
    lines = output.strip().splitlines()
    assert lines, f"{description} produced no output."
    rows = []
    for line_no, line in enumerate(lines, 1):
        parts = line.split(",")
        assert len(parts) == 3, f"Invalid CSV at {description} line {line_no}: {line!r}"
        try:
            row = tuple(float(value) for value in parts)
        except ValueError:
            pytest.fail(f"Non-numeric CSV at {description} line {line_no}: {line!r}")
        assert all(math.isfinite(value) for value in row), (
            f"Non-finite value at {description} line {line_no}: {line!r}"
        )
        rows.append(row)
    return rows


def expected_trajectory(m, k, c, t_end, dt):
    rows = []
    t = 0.0
    x = 1.0
    v = 0.0
    while t <= t_end + 1e-9:
        rows.append((t, x, v))
        ax = (-k * x - c * v) / m
        x += v * dt
        v += ax * dt
        t += dt
    return rows


def test_fast_sim_exists_executable_and_is_required_build():
    """Check fast_sim and verify it is the executable produced by the required build."""
    assert os.path.exists(FAST_SIM), f"Executable {FAST_SIM} does not exist."
    assert os.path.isfile(FAST_SIM), f"{FAST_SIM} is not a file."
    assert os.access(FAST_SIM, os.X_OK), f"{FAST_SIM} is not executable."

    with open(FAST_SIM, "rb") as f:
        submitted = f.read()
    assert submitted.startswith(b"\x7fELF"), f"{FAST_SIM} is not an ELF executable."

    expected_exe = "/tmp/fast_sim_required_build"
    compile_cmd = ["gcc", "-O3", "-lm", SIMULATOR_C, "-o", expected_exe]
    compile_res = subprocess.run(compile_cmd, capture_output=True, text=True, timeout=30)
    assert compile_res.returncode == 0, (
        f"Failed to compile {SIMULATOR_C} with gcc -O3 and -lm: {compile_res.stderr}"
    )
    with open(expected_exe, "rb") as f:
        expected_binary = f.read()
    assert submitted == expected_binary, (
        f"{FAST_SIM} is not the executable produced from simulator.c by the required "
        "gcc -O3 -lm build."
    )


def test_fast_sim_executes_correctly_on_derived_inputs():
    """Execute the submitted artifact on unpredictable inputs and derive expected answers."""
    rng = secrets.SystemRandom()
    for case_no in range(4):
        m = rng.uniform(0.55, 3.0)
        k = rng.uniform(0.4, 8.0)
        c = rng.uniform(0.01, 1.2)
        dt = rng.choice([0.005, 0.01, 0.02])
        steps = rng.randint(35, 180)
        t_end = steps * dt
        args = [f"{m:.12g}", f"{k:.12g}", f"{c:.12g}", f"{t_end:.12g}", f"{dt:.12g}"]

        actual = parse_csv_output(
            run_checked([FAST_SIM] + args), f"fast_sim dynamic case {case_no + 1}"
        )
        numeric_args = [float(value) for value in args]
        expected = expected_trajectory(*numeric_args)
        assert len(actual) == len(expected), (
            f"fast_sim dynamic case {case_no + 1} returned {len(actual)} rows; "
            f"expected {len(expected)}."
        )
        for row_no, (got, want) in enumerate(zip(actual, expected), 1):
            assert abs(got[0] - want[0]) <= 5.1e-5, (
                f"Incorrect t in dynamic case {case_no + 1}, row {row_no}: {got[0]} vs {want[0]}"
            )
            assert abs(got[1] - want[1]) <= 5.1e-7, (
                f"Incorrect x in dynamic case {case_no + 1}, row {row_no}: {got[1]} vs {want[1]}"
            )
            assert abs(got[2] - want[2]) <= 5.1e-7, (
                f"Incorrect v in dynamic case {case_no + 1}, row {row_no}: {got[2]} vs {want[2]}"
            )


def test_regression_diff_correct():
    """Re-run both required solvers and verify the reported maximum x difference."""
    diff_file = os.path.join(ODE_DIR, "regression_diff.txt")
    assert os.path.exists(diff_file), f"File {diff_file} does not exist."

    with open(diff_file, "r") as f:
        content = f.read().strip()
    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Content of {diff_file} is not a valid float: {content!r}")

    assert val < 1e-4, f"The maximum absolute difference {val} is too large or incorrect."
    assert val >= 0.0, f"The maximum absolute difference {val} cannot be negative."

    args = ["1.0", "2.0", "0.5", "10.0", "0.01"]
    fast_rows = parse_csv_output(run_checked([FAST_SIM] + args), "fast_sim regression run")
    baseline_rows = parse_csv_output(
        run_checked(["python3", BASELINE] + args), "baseline regression run"
    )
    assert len(fast_rows) == len(baseline_rows), "Regression solver row counts differ."
    actual_max = max(abs(fast[1] - baseline[1]) for fast, baseline in zip(fast_rows, baseline_rows))
    assert abs(val - actual_max) <= 1e-15, (
        f"{diff_file} reports {val}, but executing both solvers gives {actual_max}."
    )


def test_train_data_csv_matches_expected():
    """Keep the original exact comparison for the requested training run."""
    train_data_path = os.path.join(ODE_DIR, "train_data.csv")
    assert os.path.exists(train_data_path), f"File {train_data_path} does not exist."

    expected_exe_path = "/tmp/fast_sim_expected"
    compile_cmd = ["gcc", "-O3", "-lm", SIMULATOR_C, "-o", expected_exe_path]
    compile_res = subprocess.run(compile_cmd, capture_output=True, text=True, timeout=30)
    assert compile_res.returncode == 0, f"Failed to compile {SIMULATOR_C} for verification."

    run_cmd = [expected_exe_path, "1.0", "5.0", "0.1", "20.0", "0.01"]
    expected_output = run_checked(run_cmd).strip()
    with open(train_data_path, "r") as f:
        actual_output = f.read().strip()

    expected_lines = expected_output.splitlines()
    actual_lines = actual_output.splitlines()
    assert len(actual_lines) == len(expected_lines), (
        f"Line count mismatch in {train_data_path}. Expected {len(expected_lines)} lines, "
        f"got {len(actual_lines)} lines."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Mismatch at line {i + 1} in {train_data_path}.\n"
            f"Expected: {expected}\nActual:   {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
