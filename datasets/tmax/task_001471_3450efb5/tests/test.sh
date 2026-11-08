#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import subprocess
import tempfile

import pytest

PROJECT = "/home/user/nanofit"
EXECUTABLE = os.path.join(PROJECT, "nanofit")
RESULTS = "/home/user/results.csv"


def euler_integration(k, y0, tEnd, dt=0.001):
    y = y0
    t = 0.0
    while t < tEnd - 1e-9:
        y = y - dt * k * y
        t += dt
    return y


def exact_go_loop_integration(k, y0, t_end, dt=0.001):
    y = y0
    t = 0.0
    while t < t_end:
        y = y - dt * k * y
        t += dt
    return y


def run(cmd, **kwargs):
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def test_ode_go_fixed():
    path = os.path.join(PROJECT, "ode.go")
    assert os.path.isfile(path), f"{path} is missing"
    with open(path, "r") as f:
        content = f.read()
    assert "dt = dt * 1.5" not in content, "The bug 'dt = dt * 1.5' is still present in ode.go"
    assert re.search(r"\bdt\s*:=\s*0\.001\b", content), (
        "IntegrateODE must use the requested constant step size dt := 0.001"
    )


def test_go_test_passes():
    result = subprocess.run(
        ["go", "test"],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"'go test' failed with output:\n{result.stdout}\n{result.stderr}"


def test_integrator_on_hidden_cases():
    rng = random.SystemRandom()
    cases = []
    for _ in range(8):
        cases.append((
            rng.uniform(0.15, 12.0),
            rng.uniform(3.0, 250.0),
            rng.uniform(0.0023, 1.35),
        ))

    case_text = ",\n".join(
        "        {%r, %r, %r}" % case for case in cases
    )
    hidden_test = f'''package main

import (
    "math"
    "testing"
)

func verifierEuler(k, y0, tEnd float64) float64 {{
    y := y0
    t := 0.0
    const dt = 0.001
    for t < tEnd {{
        y = y - dt*k*y
        t += dt
    }}
    return y
}}

func TestVerifierHiddenIntegrationCases(t *testing.T) {{
    cases := [][3]float64{{
{case_text}
    }}
    for _, c := range cases {{
        got := IntegrateODE(c[0], c[1], c[2])
        want := verifierEuler(c[0], c[1], c[2])
        tolerance := 1e-13 * math.Max(1, math.Abs(want))
        if math.IsNaN(got) || math.IsInf(got, 0) || math.Abs(got-want) > tolerance {{
            t.Fatalf("IntegrateODE(%g, %g, %g) = %.17g; want %.17g", c[0], c[1], c[2], got, want)
        }}
    }}
}}
'''
    hidden_path = os.path.join(PROJECT, "verifier_dynamic_test.go")
    assert not os.path.exists(hidden_path), f"Unexpected pre-existing file: {hidden_path}"
    try:
        with open(hidden_path, "w") as f:
            f.write(hidden_test)
        run(["go", "test", "-run", "TestVerifierHiddenIntegrationCases", "-count=1"], cwd=PROJECT)
    finally:
        try:
            os.remove(hidden_path)
        except FileNotFoundError:
            pass


def test_executable_exists():
    path = EXECUTABLE
    assert os.path.isfile(path), f"Compiled executable {path} is missing"
    assert os.access(path, os.X_OK), f"File {path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable"
    info = run(["go", "version", "-m", path])
    assert "nanofit" in info.stdout, f"{path} is not identifiable as the nanofit Go program"


def test_executable_on_unseen_input_and_matches_source_build():
    rng = random.SystemRandom()
    records = []
    for i in range(7):
        records.append((
            f"hidden_{rng.randrange(10**8, 10**9)}_{i}",
            rng.uniform(0.2, 11.5),
            rng.uniform(5.0, 220.0),
            rng.uniform(0.0037, 1.2),
        ))

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "input.csv")
        existing_output = os.path.join(td, "existing.csv")
        rebuilt_output = os.path.join(td, "rebuilt.csv")
        rebuilt_binary = os.path.join(td, "nanofit-rebuilt")

        with open(input_path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "decay_rate", "initial_signal", "time_end"])
            writer.writerows(records)

        run(["go", "build", "-o", rebuilt_binary, "."], cwd=PROJECT)
        run([EXECUTABLE, "--input", input_path, "--output", existing_output], cwd=PROJECT)
        run([rebuilt_binary, "--input", input_path, "--output", rebuilt_output], cwd=PROJECT)

        with open(existing_output, "rb") as f:
            existing_bytes = f.read()
        with open(rebuilt_output, "rb") as f:
            rebuilt_bytes = f.read()
        assert existing_bytes == rebuilt_bytes, (
            "The submitted executable does not behave like a fresh build of the submitted source"
        )

        with open(existing_output, newline="") as f:
            rows = list(csv.reader(f))
        assert rows and rows[0] == ["id", "final_signal"]
        assert len(rows) == len(records) + 1
        actual = {row[0]: float(row[1]) for row in rows[1:]}
        assert len(actual) == len(records), "Output contains missing or duplicate IDs"
        for seq_id, k, y0, t_end in records:
            expected = float(f"{exact_go_loop_integration(k, y0, t_end):.6f}")
            assert seq_id in actual
            assert math.isfinite(actual[seq_id])
            assert abs(actual[seq_id] - expected) < 5e-7, (
                f"Incorrect result for unseen input {seq_id}: expected {expected:.6f}, got {actual[seq_id]:.6f}"
            )


def test_results_csv_correct():
    try:
        os.remove(RESULTS)
    except FileNotFoundError:
        pass

    run([
        EXECUTABLE,
        "--input", "/home/user/nanofit/data/signals.csv",
        "--output", RESULTS,
    ], cwd=PROJECT)

    path = RESULTS
    assert os.path.isfile(path), f"Results file {path} is missing"

    expected_results = {
        "seq1": euler_integration(5.0, 100.0, 2.0),
        "seq2": euler_integration(2.5, 50.0, 4.0),
        "seq3": euler_integration(10.0, 200.0, 1.0),
    }

    with open(path, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "results.csv is empty"
    assert rows[0] == ["id", "final_signal"], "Header in results.csv is incorrect"

    parsed_results = {}
    for row in rows[1:]:
        assert len(row) == 2, f"Malformed row in results.csv: {row}"
        parsed_results[row[0]] = float(row[1])

    for seq_id, expected_val in expected_results.items():
        assert seq_id in parsed_results, f"{seq_id} missing from results.csv"
        actual_val = parsed_results[seq_id]
        assert abs(actual_val - expected_val) < 1e-4, (
            f"Value for {seq_id} is incorrect. Expected approx {expected_val:.6f}, got {actual_val}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
