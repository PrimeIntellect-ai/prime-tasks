#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

PROJECT = "/home/user/seq_model"
MAIN_RS = os.path.join(PROJECT, "src/main.rs")
FINAL_FILE = "/home/user/final_population.txt"


def parse_vector(content, source):
    parts = content.strip().split(',')
    assert len(parts) == 3, f"Expected 3 values in {source}, found {len(parts)}"
    try:
        vals = [float(x.strip()) for x in parts]
    except ValueError:
        assert False, f"Could not parse {source} as a comma-separated list of floats"
    assert all(math.isfinite(v) for v in vals), f"{source} contains NaN or inf"
    return vals


def reference_result():
    a = (
        (-0.5, 0.1, 0.0),
        (0.2, -0.3, 0.1),
        (0.0, 0.2, -0.4),
    )
    state = [100.0, 50.0, 25.0]
    t = 0.0
    t_end = 5.0
    dt = 0.1
    tol = 1e-3

    def mat_vec(v):
        return [sum(a[i][j] * v[j] for j in range(3)) for i in range(3)]

    iterations = 0
    while t < t_end:
        iterations += 1
        assert iterations < 1000000, "Reference integration failed to converge"
        if t + dt > t_end:
            dt = t_end - t
        k1 = mat_vec(state)
        predictor = [state[i] + k1[i] * dt for i in range(3)]
        k2 = mat_vec(predictor)
        corrector = [state[i] + (k1[i] + k2[i]) * (dt / 2.0) for i in range(3)]
        error = math.sqrt(sum((corrector[i] - predictor[i]) ** 2 for i in range(3)))
        if error > tol:
            dt *= 0.5
        else:
            state = corrector
            t += dt
            dt *= 1.2
    return state


def test_final_population_file_exists():
    assert os.path.isfile(FINAL_FILE), "/home/user/final_population.txt is missing"


def test_final_population_values():
    with open(FINAL_FILE, "r") as f:
        vals = parse_vector(f.read(), FINAL_FILE)

    expected = [16.89, 25.69, 8.51]
    for i, (v, e) in enumerate(zip(vals, expected)):
        assert abs(v - e) <= 0.1, f"Value at index {i} ({v}) deviates too much from expected ({e})"


def test_main_rs_fixed():
    assert os.path.isfile(MAIN_RS), f"{MAIN_RS} is missing"
    with open(MAIN_RS, "r") as f:
        content = f.read()

    assert "error > tol" in content, "Error tolerance check not found in main.rs"

    # Strip comments before checking that the requested updates occur in the
    # actual if/else branches rather than merely appearing in comments.
    code = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    code = re.sub(r"//[^\n]*", "", code)
    branch = re.search(
        r"if\s+error\s*>\s*tol\s*\{(?P<high>[^{}]*)\}\s*else\s*\{(?P<ok>[^{}]*)\}",
        code,
        flags=re.S,
    )
    assert branch, "Could not find the adaptive error if/else logic"
    high = branch.group("high")
    ok = branch.group("ok")
    assert re.search(r"\bdt\s*\*=\s*0\.5(?:0*)?\s*;", high), "High-error branch must halve dt"
    assert not re.search(r"\bdt\s*\*=\s*1\.2(?:0*)?\s*;", high), "High-error branch still increases dt"
    assert re.search(r"\bstate\s*=\s*corrector\s*;", ok), "Accepted-step branch must advance state"
    assert re.search(r"\bt\s*\+=\s*dt\s*;", ok), "Accepted-step branch must advance time"
    assert re.search(r"\bdt\s*\*=\s*1\.2(?:0*)?\s*;", ok), "Accepted-step branch must increase dt by 20%"
    assert not re.search(r"\bdt\s*\*=\s*0\.5(?:0*)?\s*;", ok), "Accepted-step branch still halves dt"


def test_project_compiles_runs_and_matches_saved_result():
    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, f"cargo run failed:\n{result.stderr}\n{result.stdout}"
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert lines, "The simulation produced no output"
    run_vals = parse_vector(lines[-1], "the simulation output")

    reference = reference_result()
    for i, (actual, expected) in enumerate(zip(run_vals, reference)):
        assert abs(actual - expected) <= 1e-4, (
            f"Simulation value at index {i} ({actual}) does not match the independently computed result ({expected})"
        )

    with open(FINAL_FILE, "r") as f:
        saved_vals = parse_vector(f.read(), FINAL_FILE)
    for i, (saved, actual) in enumerate(zip(saved_vals, run_vals)):
        assert abs(saved - actual) <= 1e-4, (
            f"Saved value at index {i} ({saved}) does not match cargo run output ({actual})"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
