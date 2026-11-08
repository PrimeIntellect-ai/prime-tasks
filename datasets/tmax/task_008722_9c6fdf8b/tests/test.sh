#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import subprocess
import tempfile

import numpy as np
from scipy.integrate import solve_ivp

EXECUTABLE = "/home/user/bin/seq_processor"
RAW_DATA = "/home/user/data/sequences.txt"
MEASUREMENTS = "/home/user/measurements.csv"
SCRIPT = "/home/user/analyze.py"
RESULTS = "/home/user/mcmc_results.json"


def expected_processor_output(path):
    lines = ["time,marker_freq"]
    with open(path, "r") as f:
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            time_text, rest = raw.split(",", 1)
            seq = rest.split()[0]
            freq = sum(base in "GC" for base in seq) / len(seq)
            lines.append(f"{float(time_text):.1f},{freq:.4f}")
    return "\n".join(lines) + "\n"


def parse_result():
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} does not exist."
    with open(RESULTS, "r") as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            assert False, "Results file is not valid JSON."

    assert "alpha" in result, "Key 'alpha' missing in results."
    assert "beta" in result, "Key 'beta' missing in results."
    assert isinstance(result["alpha"], (int, float)) and not isinstance(result["alpha"], bool), "'alpha' must be a number."
    assert isinstance(result["beta"], (int, float)) and not isinstance(result["beta"], bool), "'beta' must be a number."
    assert math.isfinite(result["alpha"]) and math.isfinite(result["beta"]), "Results must be finite."
    assert 0.0 <= result["alpha"] <= 2.0, "'alpha' is outside the prior bounds [0.0, 2.0]."
    assert 0.0 <= result["beta"] <= 2.0, "'beta' is outside the prior bounds [0.0, 2.0]."
    assert abs(result["alpha"] - round(result["alpha"], 4)) < 1e-12, "'alpha' must be rounded to 4 decimal places."
    assert abs(result["beta"] - round(result["beta"], 4)) < 1e-12, "'beta' must be rounded to 4 decimal places."
    return result


def run_analysis():
    if os.path.exists(RESULTS):
        os.unlink(RESULTS)
    completed = subprocess.run(
        ["python3", SCRIPT], cwd="/home/user", capture_output=True, text=True,
        timeout=180
    )
    assert completed.returncode == 0, (
        f"analyze.py failed with exit code {completed.returncode}:\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    return parse_result()


def reference_mcmc(times, observations):
    np.random.seed(42)
    alpha = 0.5
    beta = 0.5
    samples = []

    def log_likelihood(a, b):
        def ode(t, y):
            return a * y[0] - b * t

        solution = solve_ivp(
            ode, (float(times[0]), float(times[-1])),
            [float(observations[0])], t_eval=times
        )
        assert solution.success and solution.y.shape[1] == len(times)
        residual = observations - solution.y[0]
        return -0.5 * np.sum((residual / 0.1) ** 2)

    current_ll = log_likelihood(alpha, beta)
    for _ in range(5000):
        alpha_prop = np.random.normal(alpha, 0.05)
        beta_prop = np.random.normal(beta, 0.05)
        if 0.0 <= alpha_prop <= 2.0 and 0.0 <= beta_prop <= 2.0:
            proposed_ll = log_likelihood(alpha_prop, beta_prop)
            if np.log(np.random.random()) < proposed_ll - current_ll:
                alpha, beta = alpha_prop, beta_prop
                current_ll = proposed_ll
        samples.append((alpha, beta))

    return np.mean(np.asarray(samples)[1000:], axis=0)


def read_measurements(text):
    rows = list(csv.reader(text.splitlines()))
    assert len(rows) > 1, "CSV file should have a header and data rows."
    assert rows[0] == ["time", "marker_freq"], "CSV header is incorrect."
    assert float(rows[1][0]) == 0.0, "First time point should be 0.0"
    assert abs(float(rows[1][1]) - 0.5000) < 1e-4, "First marker_freq should be 0.5000"
    assert all(len(row) == 2 for row in rows[1:]), "Each CSV data row must have two columns."
    return np.array([float(r[0]) for r in rows[1:]]), np.array([float(r[1]) for r in rows[1:]])


def assert_close_to_reference(result, reference, tolerance, label):
    assert abs(result["alpha"] - reference[0]) <= tolerance, (
        f"{label} alpha does not match the required MCMC/model calculation: "
        f"got {result['alpha']}, expected approximately {reference[0]:.4f}"
    )
    assert abs(result["beta"] - reference[1]) <= tolerance, (
        f"{label} beta does not match the required MCMC/model calculation: "
        f"got {result['beta']}, expected approximately {reference[1]:.4f}"
    )


def test_complete_workflow():
    # Preserve the original existence, permission, CSV, script, and result assertions.
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist. Did you compile the C program?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "seq_processor must be a compiled native executable."

    assert os.path.isfile(MEASUREMENTS), f"Measurements file {MEASUREMENTS} does not exist."
    with open(MEASUREMENTS, "r") as f:
        submitted_measurements = f.read()
    original_times, original_observations = read_measurements(submitted_measurements)

    # Execute the submitted processor and compare every row with values independently
    # derived from the supplied raw sequences.
    processor_run = subprocess.run(
        [EXECUTABLE, RAW_DATA], capture_output=True, text=True, timeout=30
    )
    assert processor_run.returncode == 0, "seq_processor failed on the supplied sequence data."
    independently_expected = expected_processor_output(RAW_DATA)
    assert processor_run.stdout == independently_expected, "seq_processor produced incorrect measurements."
    assert submitted_measurements == processor_run.stdout, (
        "measurements.csv is not the complete output of the compiled seq_processor."
    )

    # Exercise the executable on data not present during the task.
    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        f.write("0.0,GGGG\n1.5,ATAT\n2.0,GACT\n")
        probe_path = f.name
    try:
        probe = subprocess.run([EXECUTABLE, probe_path], capture_output=True, text=True, timeout=30)
        assert probe.returncode == 0
        assert probe.stdout == "time,marker_freq\n0.0,1.0000\n1.5,0.0000\n2.0,0.5000\n", (
            "seq_processor does not implement the required sequence-frequency calculation."
        )
    finally:
        os.unlink(probe_path)

    assert os.path.isfile(SCRIPT), f"Python script {SCRIPT} does not exist."
    with open(SCRIPT, "r") as f:
        source = f.read()
    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        assert False, f"analyze.py is not valid Python: {exc}"

    calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call)]
    assert any(
        (isinstance(c.func, ast.Name) and c.func.id == "solve_ivp") or
        (isinstance(c.func, ast.Attribute) and c.func.attr == "solve_ivp")
        for c in calls
    ), "analyze.py must use scipy.integrate.solve_ivp."
    constants = [n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, (int, float))]
    for required in (5000, 1000, 42, 0.05, 0.1, 2.0):
        assert any(float(v) == float(required) for v in constants), f"analyze.py is missing required MCMC constant {required}."

    # Run against the required data and independently recompute its expected estimate.
    original_result = run_analysis()
    original_reference = reference_mcmc(original_times, original_observations)
    assert_close_to_reference(original_result, original_reference, 0.06, "Original-data")

    # Replace only the measurements temporarily to ensure analyze.py really reads the
    # CSV and performs the model/MCMC calculation rather than emitting fixed numbers.
    synthetic_times = np.linspace(0.0, 2.0, 11)
    synthetic_solution = solve_ivp(
        lambda t, y: 0.8 * y[0] - 0.5 * t,
        (0.0, 2.0), [0.5], t_eval=synthetic_times
    ).y[0]
    synthetic_observations = synthetic_solution + np.array([0.0, 0.01, -0.015, 0.02, -0.01, 0.005, -0.02, 0.015, -0.005, 0.01, -0.01])
    synthetic_csv = "time,marker_freq\n" + "".join(
        f"{t:.6f},{m:.8f}\n" for t, m in zip(synthetic_times, synthetic_observations)
    )

    try:
        with open(MEASUREMENTS, "w") as f:
            f.write(synthetic_csv)
        synthetic_result_1 = run_analysis()
        synthetic_result_2 = run_analysis()
        assert synthetic_result_1 == synthetic_result_2, (
            "Repeated runs are not reproducible; seed numpy.random with 42 at MCMC start."
        )
        synthetic_reference = reference_mcmc(synthetic_times, synthetic_observations)
        assert_close_to_reference(synthetic_result_1, synthetic_reference, 0.04, "Probe-data")
    finally:
        with open(MEASUREMENTS, "w") as f:
            f.write(processor_run.stdout)

    # Leave the required final result corresponding to the supplied measurements.
    final_result = run_analysis()
    assert final_result == original_result, "Final run on the supplied measurements was not reproducible."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
