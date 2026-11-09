#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import stat
import subprocess
import textwrap

import pytest

ROOT = "/home/user/simulation"


@pytest.fixture(scope="session", autouse=True)
def run_pipeline():
    script = os.path.join(ROOT, "run_pipeline.sh")
    assert os.path.isfile(script), f"{script} does not exist."
    assert os.stat(script).st_mode & stat.S_IXUSR, f"{script} is not executable."

    # Ensure all tested artifacts are freshly produced by the submitted pipeline.
    for name in ("sim", "cpu.prof", "output.csv", "metric.log"):
        path = os.path.join(ROOT, name)
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                pytest.fail(f"Expected artifact path {path} is a directory")
            os.remove(path)

    result = subprocess.run(
        [script], cwd=ROOT, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=60
    )
    assert result.returncode == 0, "run_pipeline.sh failed:\n" + result.stdout


def test_integrator_fixed():
    integrator_path = os.path.join(ROOT, "integrator.go")
    assert os.path.isfile(integrator_path), f"{integrator_path} is missing."

    with open(integrator_path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "tol / err" in content or "tol/err" in content, "The step size adaptation logic was not correctly inverted to (tol / err)."
    assert "0.1" in content, "Clamping upper bound (0.1) not found in integrator.go."
    assert "1e-6" in content, "Clamping lower bound (1e-6) not found in integrator.go."

    # Exercise solveODE from the submitted Go package. This checks the actual
    # adaptation direction and both clamp bounds, and verifies output.csv is the
    # requested reshape of solveODE's flat result.
    verifier_test = os.path.join(ROOT, "verifier_behavior_test.go")
    source = r'''
package main

import (
    "encoding/csv"
    "math"
    "os"
    "strconv"
    "testing"
)

func closeEnough(a, b float64) bool {
    if math.IsNaN(a) || math.IsNaN(b) || math.IsInf(a, 0) || math.IsInf(b, 0) {
        return false
    }
    return math.Abs(a-b) <= 1e-10*math.Max(1, math.Max(math.Abs(a), math.Abs(b)))
}

func TestVerifierAdaptiveBehavior(t *testing.T) {
    flat := solveODE(0.0, 2.0, 10.0, 1e-3)
    if len(flat) < 4 || len(flat)%2 != 0 {
        t.Fatalf("solveODE returned malformed flat data of length %d", len(flat))
    }
    if len(flat) > 200000 {
        t.Fatalf("solver hit the old safety limit instead of converging")
    }

    yEuler := 2.0 + 0.01*(-0.5*2.0*2.0)
    yHeun := 2.0 + (0.01/2.0)*((-0.5*2.0*2.0)+(-0.5*yEuler*yEuler))
    err := math.Abs(yHeun-yEuler)
    expectedFirstStep := 0.01 * (1e-3 / err)
    if expectedFirstStep > 0.1 { expectedFirstStep = 0.1 }
    if expectedFirstStep < 1e-6 { expectedFirstStep = 1e-6 }
    if !closeEnough(flat[2], expectedFirstStep) {
        t.Fatalf("first adapted step is %g, expected %g from dt*(tol/err)", flat[2], expectedFirstStep)
    }

    upper := solveODE(0.0, 2.0, 0.11, 1.0)
    if len(upper) < 4 || !closeEnough(upper[2], 0.1) {
        t.Fatalf("upper clamp is not effective; second time is %v", func() interface{} { if len(upper) >= 3 { return upper[2] }; return "missing" }())
    }

    lower := solveODE(0.0, 2.0, 1.1e-6, 1e-20)
    if len(lower) < 4 || !closeEnough(lower[2], 1e-6) {
        t.Fatalf("lower clamp is not effective; second time is %v", func() interface{} { if len(lower) >= 3 { return lower[2] }; return "missing" }())
    }

    f, errOpen := os.Open("output.csv")
    if errOpen != nil { t.Fatal(errOpen) }
    defer f.Close()
    rows, errRead := csv.NewReader(f).ReadAll()
    if errRead != nil { t.Fatal(errRead) }
    if len(rows) != len(flat)/2 {
        t.Fatalf("output.csv has %d rows, expected %d from solveODE", len(rows), len(flat)/2)
    }
    for i, row := range rows {
        if len(row) != 2 { t.Fatalf("row %d has %d columns", i+1, len(row)) }
        gotT, e1 := strconv.ParseFloat(row[0], 64)
        gotY, e2 := strconv.ParseFloat(row[1], 64)
        if e1 != nil || e2 != nil || !closeEnough(gotT, flat[2*i]) || !closeEnough(gotY, flat[2*i+1]) {
            t.Fatalf("row %d is not the [time,state] reshape of solveODE", i+1)
        }
        if i > 0 {
            step := gotT-flat[2*(i-1)]
            if step < 1e-6-1e-12 || step > 0.1+1e-12 {
                t.Fatalf("time step at row %d is outside clamp bounds: %g", i+1, step)
            }
        }
    }
}
'''
    with open(verifier_test, "w") as f:
        f.write(source)
    try:
        result = subprocess.run(
            ["go", "test", "-run", "^TestVerifierAdaptiveBehavior$", "-count=1", "."],
            cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=30
        )
        assert result.returncode == 0, "Integrator behavior test failed:\n" + result.stdout
    finally:
        if os.path.exists(verifier_test):
            os.remove(verifier_test)


def test_pipeline_script():
    script_path = os.path.join(ROOT, "run_pipeline.sh")
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."

    sim_path = os.path.join(ROOT, "sim")
    assert os.path.isfile(sim_path), "The pipeline did not build the sim executable."
    assert os.access(sim_path, os.X_OK), "The built sim artifact is not executable."
    result = subprocess.run(
        ["go", "version", "-m", sim_path], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
    )
    assert result.returncode == 0, "sim is not a valid Go executable:\n" + result.stdout


def test_cpu_profile_generated():
    prof_path = os.path.join(ROOT, "cpu.prof")
    assert os.path.isfile(prof_path), f"{prof_path} was not generated. Ensure run_pipeline.sh runs the app with profiling enabled."
    assert os.path.getsize(prof_path) > 0, f"{prof_path} is empty."

    result = subprocess.run(
        ["go", "tool", "pprof", "-top", os.path.join(ROOT, "sim"), prof_path],
        cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=20
    )
    assert result.returncode == 0, "cpu.prof is not a valid Go CPU profile:\n" + result.stdout


def read_numeric_csv(path):
    with open(path, "r") as f:
        rows = list(csv.reader(f))
    return rows


def test_output_csv_format():
    out_path = os.path.join(ROOT, "output.csv")
    assert os.path.isfile(out_path), f"{out_path} does not exist."
    rows = read_numeric_csv(out_path)
    assert len(rows) > 0, f"{out_path} is empty."

    previous_t = None
    for i, row in enumerate(rows):
        assert len(row) == 2, f"Expected exactly 2 columns in {out_path} (time, state), but row {i+1} has {len(row)} columns."
        try:
            t, y = float(row[0]), float(row[1])
        except ValueError:
            pytest.fail(f"Non-float values found in {out_path} at row {i+1}: {row}")
        assert math.isfinite(t) and math.isfinite(y), f"Non-finite value in row {i+1}: {row}"
        if previous_t is not None:
            assert t > previous_t, f"Simulation times are not strictly increasing at row {i+1}."
        previous_t = t


def test_metric_log():
    metric_path = os.path.join(ROOT, "metric.log")
    assert os.path.isfile(metric_path), f"{metric_path} does not exist."
    with open(metric_path, "r") as f:
        content = f.read().strip()
    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"{metric_path} does not contain a valid float. Found: '{content}'")

    assert math.isfinite(val), f"Metric value is not finite: {val}"
    assert val < 0.1, f"Metric value {val} is suspiciously high (>= 0.1). The 1-Wasserstein distance approximation should be small if the simulation is correct."

    simulated_rows = read_numeric_csv(os.path.join(ROOT, "output.csv"))
    observed_rows = read_numeric_csv(os.path.join(ROOT, "observational_data.csv"))
    simulated = sorted(float(row[1]) for row in simulated_rows)
    observed = sorted(float(row[-1]) for row in observed_rows if row)
    n = min(len(simulated), len(observed))
    assert n > 0, "Cannot compute Wasserstein distance from empty data."
    expected = sum(abs(simulated[i] - observed[i]) for i in range(n)) / n
    assert math.isclose(val, expected, rel_tol=1e-9, abs_tol=1e-9), (
        f"metric.log contains {val}, but recomputing the requested Wasserstein "
        f"approximation from output.csv and observational_data.csv gives {expected}."
    )
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
