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
import sys

import pytest

PARAMS_FILE = "/home/user/params.json"
RESULTS_FILE = "/home/user/results.csv"
SIMULATE_SCRIPT = "/home/user/simulate.py"
FASTA_FILE = "/home/user/target.fasta"


def compute_expected_params():
    if not os.path.exists(FASTA_FILE):
        return 0.65, 1.3
    with open(FASTA_FILE, "r") as f:
        lines = [line.strip() for line in f if not line.startswith(">")]
    seq = "".join(lines).upper()
    if not seq:
        return 0.65, 1.3
    gc_count = seq.count("G") + seq.count("C")
    gc_frac = gc_count / len(seq)
    return gc_frac, 2.0 * gc_frac


def names_in(node):
    return {n.id for n in ast.walk(node) if isinstance(n, ast.Name)}


def target_names(node):
    if isinstance(node, ast.Name):
        return {node.id}
    if isinstance(node, ast.Subscript):
        return names_in(node.value)
    if isinstance(node, (ast.Tuple, ast.List)):
        result = set()
        for elt in node.elts:
            result.update(target_names(elt))
        return result
    return set()


def has_numerical_integration(tree):
    integrators = {"solve_ivp", "odeint", "ode", "RK23", "RK45", "DOP853", "LSODA"}
    aliases = set(integrators)
    module_aliases = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module and node.module.startswith("scipy.integrate"):
            for item in node.names:
                if item.name in integrators:
                    aliases.add(item.asname or item.name)
        elif isinstance(node, ast.Import):
            for item in node.names:
                if item.name == "scipy.integrate":
                    module_aliases.add(item.asname or "scipy")

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in aliases:
            return True
        if isinstance(node.func, ast.Attribute) and node.func.attr in integrators:
            return True

    # Accept a custom Euler/Runge-Kutta-style recurrence. A state variable must
    # participate in a cyclic update inside a loop, and the update must contain
    # multiplication or division (as a time-step/ODE update normally does).
    for loop in (n for n in ast.walk(tree) if isinstance(n, (ast.For, ast.While))):
        edges = {}
        arithmetic = False
        for node in ast.walk(loop):
            if isinstance(node, ast.Assign):
                rhs_names = names_in(node.value)
                if any(isinstance(x, (ast.Mult, ast.Div)) for x in ast.walk(node.value)):
                    arithmetic = True
                for target in node.targets:
                    for name in target_names(target):
                        edges.setdefault(name, set()).update(rhs_names)
            elif isinstance(node, ast.AugAssign):
                lhs = target_names(node.target)
                rhs_names = names_in(node.value) | lhs
                if any(isinstance(x, (ast.Mult, ast.Div)) for x in ast.walk(node.value)):
                    arithmetic = True
                for name in lhs:
                    edges.setdefault(name, set()).update(rhs_names)

        if not arithmetic:
            continue
        for start in edges:
            pending = list(edges[start])
            seen = set()
            while pending:
                current = pending.pop()
                if current == start:
                    return True
                if current not in seen:
                    seen.add(current)
                    pending.extend(edges.get(current, ()))
    return False


def validate_script():
    assert os.path.isfile(SIMULATE_SCRIPT), f"Script {SIMULATE_SCRIPT} is missing."
    assert os.path.getsize(SIMULATE_SCRIPT) > 0, f"Script {SIMULATE_SCRIPT} is empty."
    with open(SIMULATE_SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SIMULATE_SCRIPT)
    except SyntaxError as exc:
        pytest.fail(f"{SIMULATE_SCRIPT} is not valid Python: {exc}")
    assert has_numerical_integration(tree), (
        "simulate.py must contain a real numerical ODE integration using scipy.integrate "
        "or a custom Euler/Runge-Kutta-style state recurrence."
    )


def run_pipeline():
    for path in (PARAMS_FILE, RESULTS_FILE):
        if os.path.lexists(path):
            os.remove(path)
    try:
        completed = subprocess.run(
            [sys.executable, SIMULATE_SCRIPT],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("simulate.py timed out after 30 seconds.")
    assert completed.returncode == 0, (
        f"simulate.py exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def validate_outputs():
    assert os.path.isfile(PARAMS_FILE), f"File {PARAMS_FILE} is missing."
    with open(PARAMS_FILE, "r") as f:
        try:
            params = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{PARAMS_FILE} is not valid JSON.")

    assert isinstance(params, dict), "params.json must contain a JSON object."
    assert set(params.keys()) == {"gc_fraction", "r"}, (
        "params.json must contain exactly the keys 'gc_fraction' and 'r'."
    )
    assert type(params["gc_fraction"]) is float, "gc_fraction must be a float."
    assert type(params["r"]) is float, "r must be a float."
    assert math.isfinite(params["gc_fraction"]) and math.isfinite(params["r"]), (
        "Parameters must be finite numbers."
    )

    expected_gc, expected_r = compute_expected_params()
    assert math.isclose(params["gc_fraction"], expected_gc, rel_tol=1e-4), (
        f"Expected gc_fraction ~{expected_gc}, got {params['gc_fraction']}"
    )
    assert math.isclose(params["r"], expected_r, rel_tol=1e-4), (
        f"Expected r ~{expected_r}, got {params['r']}"
    )

    assert os.path.isfile(RESULTS_FILE), f"File {RESULTS_FILE} is missing."
    with open(RESULTS_FILE, "r", newline="") as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail(f"{RESULTS_FILE} is empty.")
        assert headers == ["t", "y_num", "y_exact"], (
            f"Incorrect headers. Expected ['t', 'y_num', 'y_exact'], got {headers}"
        )
        rows = list(reader)

    assert len(rows) == 11, f"Expected 11 rows (t=0..10), got {len(rows)}"
    K = 1000.0
    y0 = 1.0
    for i, row in enumerate(rows):
        assert len(row) == 3, f"Row {i} does not have exactly 3 columns."
        try:
            t = float(row[0])
            y_num = float(row[1])
            y_exact = float(row[2])
        except ValueError:
            pytest.fail(f"Non-numeric values in row {i}: {row}")
        assert all(math.isfinite(x) for x in (t, y_num, y_exact)), f"Non-finite value in row {i}: {row}"
        assert math.isclose(t, i, abs_tol=1e-5), f"Expected t={i}, got {t}"
        true_exact = K / (1 + (K / y0 - 1) * math.exp(-expected_r * t))
        assert math.isclose(y_exact, true_exact, rel_tol=1e-2), (
            f"At t={t}, expected y_exact ~{true_exact}, got {y_exact}"
        )
        error = abs(y_num - true_exact) / true_exact
        assert error < 0.01, (
            f"At t={t}, numerical value {y_num} differs from exact {true_exact} "
            f"by >= 1% (error: {error:.2%})"
        )


def test_pipeline_executes_and_handles_derived_inputs():
    validate_script()
    with open(FASTA_FILE, "rb") as f:
        original = f.read()

    cases = [
        original,
        b">derived_half_gc\nGCGC\nATAT\n",
        b">derived_high_gc\nGCGCGCGC\nAA\n",
    ]
    try:
        for fasta in cases:
            with open(FASTA_FILE, "wb") as f:
                f.write(fasta)
            run_pipeline()
            validate_outputs()
    finally:
        with open(FASTA_FILE, "wb") as f:
            f.write(original)

    # Leave the requested outputs corresponding to the original target.
    run_pipeline()
    validate_outputs()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
