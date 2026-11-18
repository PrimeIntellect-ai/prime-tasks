#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import os
import re
import runpy
import subprocess

import matplotlib.image as mpimg
import numpy as np
import pytest
import scipy.integrate

SIMULATE = "/home/user/simulate.py"
FASTA = "/home/user/gene.fasta"
FINAL = "/home/user/final_protein.txt"
PLOT = "/home/user/protein_plot.png"
STUDENT_TEST = "/home/user/test_simulate.py"


def analytical_final(gc, t=10.0):
    k_tx = gc * 10.0
    k_deg_m = 1000.0
    k_tl = 10.0
    k_deg_p = 0.1
    return (k_tl * k_tx / k_deg_m) * (
        (1.0 - math.exp(-k_deg_p * t)) / k_deg_p
        - (math.exp(-k_deg_p * t) - math.exp(-k_deg_m * t))
          / (k_deg_m - k_deg_p)
    )


def write_fasta(sequence):
    with open(FASTA, "w") as f:
        f.write(">verification_sequence\n" + sequence + "\n")


def run_script_instrumented(gc):
    calls = []
    real_solve_ivp = scipy.integrate.solve_ivp

    def checked_solve_ivp(fun, t_span, y0, *args, **kwargs):
        method = kwargs.get("method", args[0] if args else "RK45")
        assert str(method).upper() in {"BDF", "RADAU", "LSODA"}, \
            f"solve_ivp must use a stiff method, got {method!r}"
        assert len(t_span) == 2
        assert math.isclose(float(t_span[0]), 0.0, abs_tol=1e-12)
        assert math.isclose(float(t_span[1]), 10.0, abs_tol=1e-12)
        assert np.allclose(np.asarray(y0, dtype=float), [0.0, 0.0])

        ode_args = kwargs.get("args", ())
        for y in ([0.0, 0.0], [0.007, 0.23], [0.013, 0.41]):
            got = np.asarray(fun(0.37, np.asarray(y, dtype=float), *ode_args), dtype=float)
            expected = np.asarray([
                gc * 10.0 - 1000.0 * y[0],
                10.0 * y[0] - 0.1 * y[1],
            ])
            assert got.shape == (2,)
            assert np.allclose(got, expected, rtol=1e-11, atol=1e-11), \
                f"ODE equations or parameters were changed: got {got}, expected {expected}"

        calls.append(method)
        return real_solve_ivp(fun, t_span, y0, *args, **kwargs)

    scipy.integrate.solve_ivp = checked_solve_ivp
    try:
        runpy.run_path(SIMULATE, run_name="__main__")
    finally:
        scipy.integrate.solve_ivp = real_solve_ivp

    assert calls, "Running simulate.py did not call scipy.integrate.solve_ivp"


def run_script_plain():
    runpy.run_path(SIMULATE, run_name="__main__")


def assert_generated_outputs(gc):
    assert os.path.isfile(FINAL), f"File {FINAL} is missing."
    content = open(FINAL).read().strip()
    assert re.fullmatch(r"[+-]?(?:\d+\.\d{4})", content), \
        f"Final concentration must be written with exactly four decimal places, got {content!r}"
    value = float(content)
    expected_text = f"{analytical_final(gc):.4f}"
    assert content == expected_text, f"Expected {expected_text}, got {content}"
    assert math.isfinite(value) and value > 0

    assert os.path.isfile(PLOT), f"File {PLOT} is missing. Did you save the plot?"
    assert os.path.getsize(PLOT) > 0, f"File {PLOT} is empty."
    image = mpimg.imread(PLOT)
    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10, \
        "protein_plot.png is not a valid nontrivial image"
    assert np.isfinite(image).all()
    assert float(np.max(image)) > float(np.min(image)), "The plot image is blank"


def test_script_behavior_and_generated_artifacts():
    assert os.path.isfile(SIMULATE), f"File {SIMULATE} is missing."
    original_fasta = open(FASTA, "rb").read()

    # Use a verifier-selected, non-default GC fraction so precomputed output files
    # cannot satisfy the test.
    random_byte = os.urandom(1)[0]
    length = 37
    gc_count = 3 + (random_byte % 32)
    sequence = "G" * gc_count + "A" * (length - gc_count)
    gc = gc_count / length

    try:
        write_fasta(sequence)
        for path in (FINAL, PLOT):
            if os.path.exists(path):
                os.remove(path)
        run_script_instrumented(gc)
        assert_generated_outputs(gc)
    finally:
        with open(FASTA, "wb") as f:
            f.write(original_fasta)
        # Leave the required deliverables corresponding to the supplied gene.
        run_script_plain()


def test_final_protein_txt():
    path = FINAL
    assert os.path.isfile(path), f"File {path} is missing. Did you write the final protein concentration?"
    with open(path, "r") as f:
        content = f.read().strip()
    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Content of {path} is not a valid float: {content!r}")
    expected = 0.3161
    assert math.isclose(val, expected, abs_tol=0.005), \
        f"Expected final protein concentration close to {expected}, but got {val}"


def test_protein_plot_exists():
    path = PLOT
    assert os.path.isfile(path), f"File {path} is missing. Did you save the plot?"
    assert os.path.getsize(path) > 0, f"File {path} is empty."


def test_pytest_simulate_passes_and_tests_integration():
    path = STUDENT_TEST
    assert os.path.isfile(path), f"Test file {path} is missing."
    result = subprocess.run(
        ["python3", "-m", "pytest", path],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, \
        f"pytest on {path} failed. Output:\n{result.stdout}\n{result.stderr}"

    source = open(path).read()
    tree = ast.parse(source, filename=path)
    tests = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
             and n.name.startswith("test")]
    assert tests, "test_simulate.py must contain at least one pytest test function"

    def call_name(call):
        fn = call.func
        if isinstance(fn, ast.Name):
            return fn.id
        if isinstance(fn, ast.Attribute):
            return fn.attr
        return ""

    meaningful = False
    for test in tests:
        nodes = list(ast.walk(test))
        calls_simulate = any(isinstance(n, ast.Call) and call_name(n) == "simulate" for n in nodes)
        asserts_finite = any(
            isinstance(n, ast.Assert) and any(
                isinstance(x, ast.Call) and call_name(x) in {"isfinite", "is_finite"}
                for x in ast.walk(n.test)
            ) for n in nodes
        )
        asserts_positive = any(
            isinstance(n, ast.Assert) and any(
                isinstance(x, ast.Compare)
                and any(isinstance(op, (ast.Gt, ast.Lt)) for op in x.ops)
                and any(isinstance(v, ast.Constant) and v.value == 0
                        for v in [x.left] + list(x.comparators))
                for x in ast.walk(n.test)
            ) for n in nodes
        )
        has_dummy_or_patch = any(
            (isinstance(n, ast.Constant) and isinstance(n.value, str)
             and n.value and set(n.value.upper()) <= set("ACGT"))
            or (isinstance(n, ast.Name) and n.id in {"monkeypatch", "patch", "get_gc_content"})
            or (isinstance(n, ast.Attribute) and n.attr in {"patch", "get_gc_content"})
            for n in nodes
        )
        meaningful |= calls_simulate and asserts_finite and asserts_positive and has_dummy_or_patch

    assert meaningful, \
        "A pytest test must call simulate with a dummy sequence or patched GC calculation and assert the result is finite and greater than 0"


def test_simulate_uses_solve_ivp():
    path = SIMULATE
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "solve_ivp" in content, \
        "The script does not seem to use scipy.integrate.solve_ivp as requested."
    assert "BDF" in content or "Radau" in content or "LSODA" in content, \
        "The script does not seem to specify a stiff solver (e.g., BDF, Radau, LSODA)."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
