#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import re
import subprocess
import tempfile

import pytest

C_FILE = "/home/user/simulate.c"
NOTEBOOK = "/home/user/workflow.ipynb"
DATA_FILE = "/home/user/population_data.csv"
BEST_FILE = "/home/user/best_fit.json"
VERIFY_EXE = "/home/user/verify_sim"
GRID_R = [0.1, 0.2, 0.3]
GRID_K = [300.0, 400.0, 500.0]
NUMBER_RE = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")


def read_rows(path):
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    assert rows, "CSV contains no observations"
    return [(int(row["t"]), float(row["P"])) for row in rows]


def reference_sse(path, r, K):
    rows = read_rows(path)
    assert rows[0][0] == 0
    p = rows[0][1]
    current_step = 0
    sse = 0.0

    def deriv(x):
        return r * x * (1.0 - x / K)

    for t, observed in rows:
        target_step = t * 10
        assert target_step >= current_step
        while current_step < target_step:
            dt = 0.1
            k1 = deriv(p)
            k2 = deriv(p + 0.5 * dt * k1)
            k3 = deriv(p + 0.5 * dt * k2)
            k4 = deriv(p + dt * k3)
            p += (dt / 6.0) * (k1 + 2.0 * k2 + 2.0 * k3 + k4)
            current_step += 1
        sse += (p - observed) ** 2
    return sse


def parse_numeric_stdout(result):
    assert result.returncode == 0, f"Execution failed:\n{result.stderr}"
    output = result.stdout.strip()
    assert NUMBER_RE.fullmatch(output), f"Output must contain only one numeric SSE, got: {result.stdout!r}"
    value = float(output)
    assert math.isfinite(value), f"SSE must be finite, got {value}"
    assert value >= 0.0, "SSE should be non-negative"
    return value


def assert_sse_close(actual, expected):
    tolerance = max(0.002, abs(expected) * 2e-4)
    assert abs(actual - expected) <= tolerance, (
        f"Incorrect SSE: expected {expected}, got {actual} (tolerance {tolerance})"
    )


def run_simulator(csv_path, r, K):
    result = subprocess.run(
        [VERIFY_EXE, csv_path, str(r), str(K)],
        capture_output=True,
        text=True,
        timeout=20,
    )
    return parse_numeric_stdout(result)


def expected_grid_result(path):
    candidates = []
    for r in GRID_R:
        for K in GRID_K:
            candidates.append((reference_sse(path, r, K), r, K))
    return min(candidates, key=lambda item: item[0])


def load_best_fit():
    assert os.path.isfile(BEST_FILE), f"Missing {BEST_FILE}"
    with open(BEST_FILE) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"File {BEST_FILE} is not valid JSON: {exc}")
    assert "best_r" in data, "Missing 'best_r' in best_fit.json"
    assert "best_K" in data, "Missing 'best_K' in best_fit.json"
    assert "min_sse" in data, "Missing 'min_sse' in best_fit.json"
    assert isinstance(data["min_sse"], (float, int)) and not isinstance(data["min_sse"], bool), \
        "min_sse must be a number"
    assert math.isfinite(float(data["min_sse"])), "min_sse must be finite"
    return data


def execute_workflow(tag):
    for path in (BEST_FILE, "/home/user/simulate"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    output_path = f"/tmp/executed_{tag}.ipynb"
    result = subprocess.run(
        [
            "jupyter", "nbconvert", "--to", "notebook", "--execute",
            NOTEBOOK, "--output", output_path,
            "--ExecutePreprocessor.timeout=120",
        ],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"Notebook execution failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    assert os.path.isfile("/home/user/simulate"), "Notebook did not compile /home/user/simulate"
    assert os.access("/home/user/simulate", os.X_OK), "/home/user/simulate is not executable"
    return load_best_fit()


def check_best_against_reference(data, csv_path):
    expected_sse, expected_r, expected_K = expected_grid_result(csv_path)
    assert abs(float(data["best_r"]) - expected_r) < 1e-5, (
        f"Expected best_r {expected_r}, got {data['best_r']}"
    )
    assert abs(float(data["best_K"]) - expected_K) < 1e-5, (
        f"Expected best_K {expected_K}, got {data['best_K']}"
    )
    assert_sse_close(float(data["min_sse"]), expected_sse)


def test_files_exist():
    assert os.path.isfile(C_FILE), "Missing /home/user/simulate.c"
    assert os.path.isfile(NOTEBOOK), "Missing /home/user/workflow.ipynb"
    assert os.path.isfile(BEST_FILE), "Missing /home/user/best_fit.json"


def test_best_fit_json_content():
    data = load_best_fit()
    assert abs(data["best_r"] - 0.2) < 1e-5, f"Expected best_r to be 0.2, got {data['best_r']}"
    assert abs(data["best_K"] - 400.0) < 1e-5, f"Expected best_K to be 400.0, got {data['best_K']}"


def test_c_program_compiles_and_runs():
    result = subprocess.run(
        ["gcc", "-o", VERIFY_EXE, C_FILE, "-lm"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Compilation failed:\n{result.stderr}"
    assert os.path.isfile(VERIFY_EXE), "Executable was not created after compilation"

    actual = run_simulator(DATA_FILE, 0.2, 400.0)
    expected = reference_sse(DATA_FILE, 0.2, 400.0)
    assert_sse_close(actual, expected)


def test_c_program_on_derived_inputs():
    rng = random.SystemRandom()

    # Unpredictable observation data and parameters prevent a fixed-output program
    # from passing while checking SSE at several nonconsecutive observation times.
    for index in range(3):
        r = rng.uniform(0.35, 1.8)
        K = rng.uniform(180.0, 650.0)
        rows = [(0, rng.uniform(5.0, 40.0))]
        rows.extend((t, rng.uniform(15.0, 600.0)) for t in (1, 3, 6))
        path = os.path.join(tempfile.gettempdir(), f"population_hidden_{os.getpid()}_{index}.csv")
        with open(path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["t", "P"])
            writer.writerows(rows)
        assert_sse_close(run_simulator(path, r, K), reference_sse(path, r, K))

    # Observations generated by RK4 distinguish the required dt=0.1 RK4 trajectory
    # from a hardcoded value or a different integration method.
    path = os.path.join(tempfile.gettempdir(), f"population_rk4_{os.getpid()}.csv")
    r, K, p = 3.0, 300.0, 11.0
    generated = [(0, p)]
    step = 0
    for target_t in (1, 2, 3):
        while step < target_t * 10:
            dt = 0.1
            deriv = lambda x: r * x * (1.0 - x / K)
            k1 = deriv(p)
            k2 = deriv(p + dt * k1 / 2.0)
            k3 = deriv(p + dt * k2 / 2.0)
            k4 = deriv(p + dt * k3)
            p += dt * (k1 + 2.0 * k2 + 2.0 * k3 + k4) / 6.0
            step += 1
        generated.append((target_t, p))
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["t", "P"])
        for t, value in generated:
            writer.writerow([t, format(value, ".15g")])
    assert_sse_close(run_simulator(path, r, K), reference_sse(path, r, K))


def test_notebook_executes_parameter_sweep_and_regenerates_outputs():
    with open(DATA_FILE, "rb") as f:
        original_data = f.read()

    # First execute against the supplied data and validate the actual minimum SSE.
    original_result = execute_workflow("original")
    check_best_against_reference(original_result, DATA_FILE)
    assert abs(float(original_result["best_r"]) - 0.2) < 1e-5
    assert abs(float(original_result["best_K"]) - 400.0) < 1e-5

    # Change the observations to an RK4 trajectory whose optimum is another grid
    # point. The notebook must really invoke the simulator over the parameter grid.
    dynamic_path_contents = ["t,P"]
    r_true, K_true, p = 0.3, 300.0, 10.0
    step = 0
    for t in (0, 10, 20, 30, 40, 50):
        while step < t * 10:
            dt = 0.1
            deriv = lambda x: r_true * x * (1.0 - x / K_true)
            k1 = deriv(p)
            k2 = deriv(p + dt * k1 / 2.0)
            k3 = deriv(p + dt * k2 / 2.0)
            k4 = deriv(p + dt * k3)
            p += dt * (k1 + 2.0 * k2 + 2.0 * k3 + k4) / 6.0
            step += 1
        dynamic_path_contents.append(f"{t},{p:.15g}")

    dynamic_result = None
    try:
        with open(DATA_FILE, "w") as f:
            f.write("\n".join(dynamic_path_contents) + "\n")
        dynamic_result = execute_workflow("dynamic")
        check_best_against_reference(dynamic_result, DATA_FILE)
        assert abs(float(dynamic_result["best_r"]) - 0.3) < 1e-5
        assert abs(float(dynamic_result["best_K"]) - 300.0) < 1e-5
    finally:
        with open(DATA_FILE, "wb") as f:
            f.write(original_data)
        # Leave the requested final artifacts corresponding to the supplied data.
        restored_result = execute_workflow("restored")

    check_best_against_reference(restored_result, DATA_FILE)
    assert abs(float(restored_result["best_r"]) - 0.2) < 1e-5
    assert abs(float(restored_result["best_K"]) - 400.0) < 1e-5
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
