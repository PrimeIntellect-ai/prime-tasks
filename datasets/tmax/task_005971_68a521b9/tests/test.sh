#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import shutil
import subprocess

import pytest

ODE_SOLVER = "/home/user/ode_solver.sh"
PIPELINE = "/home/user/pipeline.sh"
EXPECTED_DTS = ["2.0", "1.0", "0.5", "0.1", "0.01"]


def run_script(path, *args):
    try:
        result = subprocess.run(
            [path, *args],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"{path} timed out: {exc}")
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}. stderr: {result.stderr}"
    )
    return result.stdout


def parse_and_validate_csv(text, dt, source):
    rows = list(csv.reader(text.splitlines()))
    assert rows, f"No CSV output from {source}"
    assert rows[0] == ["t", "y_num", "y_exact", "abs_error"], (
        f"Incorrect CSV header in {source}: {rows[0]}"
    )

    steps = int(round(20.0 / dt))
    assert math.isclose(steps * dt, 20.0, rel_tol=0.0, abs_tol=1e-10)
    assert len(rows) == steps + 2, (
        f"{source} has {len(rows) - 1} data rows; expected {steps + 1}"
    )

    for i, row in enumerate(rows[1:]):
        assert len(row) == 4, f"Malformed row {i + 2} in {source}: {row}"
        try:
            t, y_num, y_exact, abs_error = map(float, row)
        except ValueError:
            pytest.fail(f"Non-numeric row {i + 2} in {source}: {row}")
        assert all(math.isfinite(v) for v in (t, y_num, y_exact, abs_error)), (
            f"Non-finite value in row {i + 2} of {source}"
        )

        expected_t = i * dt
        expected_num = 1000.0 * ((1.0 - 0.2 * dt) ** i)
        expected_exact = 1000.0 * math.exp(-0.2 * expected_t)
        expected_error = abs(expected_num - expected_exact)

        assert math.isclose(t, expected_t, rel_tol=0.0, abs_tol=5e-5), (
            f"Incorrect t in row {i + 2} of {source}: expected {expected_t}, got {t}"
        )
        assert math.isclose(y_num, expected_num, rel_tol=3e-5, abs_tol=0.002), (
            f"Incorrect Euler value at t={expected_t} in {source}: "
            f"expected {expected_num}, got {y_num}"
        )
        assert math.isclose(y_exact, expected_exact, rel_tol=3e-5, abs_tol=0.002), (
            f"Incorrect exact value at t={expected_t} in {source}: "
            f"expected {expected_exact}, got {y_exact}"
        )
        assert math.isclose(abs_error, expected_error, rel_tol=3e-5, abs_tol=0.002), (
            f"Incorrect absolute error at t={expected_t} in {source}: "
            f"expected {expected_error}, got {abs_error}"
        )

    return tuple(map(float, rows[-1]))


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline_fresh():
    assert os.path.isfile(ODE_SOLVER), f"Missing script: {ODE_SOLVER}"
    assert os.access(ODE_SOLVER, os.X_OK), f"Script is not executable: {ODE_SOLVER}"
    assert os.path.isfile(PIPELINE), f"Missing script: {PIPELINE}"
    assert os.access(PIPELINE, os.X_OK), f"Script is not executable: {PIPELINE}"

    shutil.rmtree("/home/user/data", ignore_errors=True)
    try:
        os.remove("/home/user/convergence_log.txt")
    except FileNotFoundError:
        pass
    run_script(PIPELINE)


def test_scripts_exist_and_executable():
    """Verify that the shell scripts exist and are executable."""
    assert os.path.isfile(ODE_SOLVER), f"Missing script: {ODE_SOLVER}"
    assert os.access(ODE_SOLVER, os.X_OK), f"Script is not executable: {ODE_SOLVER}"
    assert os.path.isfile(PIPELINE), f"Missing script: {PIPELINE}"
    assert os.access(PIPELINE, os.X_OK), f"Script is not executable: {PIPELINE}"


def test_solver_on_additional_inputs():
    """Execute the solver on non-pipeline step sizes and derive every expected row."""
    candidates = ["5.0", "2.5", "1.25", "0.8", "0.625", "0.4", "0.25", "0.2", "0.16", "0.125", "0.08", "0.05"]
    for dt_string in random.SystemRandom().sample(candidates, 3):
        output = run_script(ODE_SOLVER, dt_string)
        parse_and_validate_csv(output, float(dt_string), f"ode_solver.sh {dt_string}")


def test_data_directory_and_csv_files():
    """Verify all pipeline datasets, including every numerical row."""
    data_dir = "/home/user/data"
    assert os.path.isdir(data_dir), f"Data directory missing: {data_dir}"

    for dt_string in EXPECTED_DTS:
        file_path = os.path.join(data_dir, f"dataset_dt_{dt_string}.csv")
        assert os.path.isfile(file_path), f"Missing dataset file: {file_path}"

        with open(file_path, "r", newline="") as f:
            text = f.read()
        lines = text.splitlines()
        assert len(lines) > 1, f"Dataset file {file_path} is empty or missing data rows."
        header = lines[0].strip()
        assert header == "t,y_num,y_exact,abs_error", (
            f"Incorrect CSV header in {file_path}. Found: {header}"
        )
        parse_and_validate_csv(text, float(dt_string), file_path)


def test_convergence_log():
    """Verify the convergence log format, numerical accuracy, and dataset provenance."""
    log_file = "/home/user/convergence_log.txt"
    assert os.path.isfile(log_file), f"Missing convergence log: {log_file}"

    with open(log_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) >= 6, "Convergence log has insufficient lines. Expected at least 6 (header + 5 values)."
    assert lines[0] == "dt,final_abs_error", (
        f"Incorrect header in convergence log. Found: {lines[0]}"
    )

    exact_y = 1000.0 * math.exp(-4.0)
    expected_errors = {}
    for dt in [2.0, 1.0, 0.5, 0.1, 0.01]:
        steps = int(20.0 / dt)
        y_num = 1000.0 * ((1.0 - 0.2 * dt) ** steps)
        expected_errors[str(dt)] = abs(y_num - exact_y)

    log_data = {}
    for line in lines[1:]:
        parts = line.split(",")
        if len(parts) == 2:
            dt_str, err_str = parts
            try:
                log_data[dt_str] = float(err_str)
            except ValueError:
                pass

    for dt_str, expected_err in expected_errors.items():
        assert dt_str in log_data, f"Missing dt={dt_str} in convergence log."
        actual_err = log_data[dt_str]
        assert abs(actual_err - expected_err) < 0.05, (
            f"Numerical error mismatch for dt={dt_str}. "
            f"Expected approx {expected_err:.5f}, got {actual_err:.5f}"
        )

        dataset = f"/home/user/data/dataset_dt_{dt_str}.csv"
        with open(dataset, "r", newline="") as f:
            rows = list(csv.reader(f))
        final_dataset_error = float(rows[-1][3])
        assert math.isclose(actual_err, final_dataset_error, rel_tol=3e-5, abs_tol=0.002), (
            f"Convergence log value for dt={dt_str} was not extracted from its dataset"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
