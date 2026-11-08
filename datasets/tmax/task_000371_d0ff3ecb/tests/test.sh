#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import runpy
import sys

import numpy as np
import pytest

SCRIPT_PATH = "/home/user/mcmc_sampler.py"
SUMMARY_PATH = "/home/user/posterior_summary.json"
EXPECTED_ANALYTICAL = 72 / 104.0
CAPTURED_ARRAYS = []


def _capture_frame(frame):
    if os.path.realpath(frame.f_code.co_filename) != SCRIPT_PATH:
        return
    for value in frame.f_locals.values():
        if not isinstance(value, (list, tuple, np.ndarray)):
            continue
        try:
            size = len(value)
        except Exception:
            continue
        if size not in (100000, 110000):
            continue
        try:
            arr = np.asarray(value, dtype=float)
        except Exception:
            continue
        if arr.ndim == 1 and arr.size == size:
            CAPTURED_ARRAYS.append(arr.copy())


def _trace(frame, event, arg):
    if event in ("return", "exception"):
        _capture_frame(frame)
        if event == "return" and isinstance(arg, (list, tuple, np.ndarray)):
            try:
                arr = np.asarray(arg, dtype=float)
                if arr.ndim == 1 and arr.size in (100000, 110000):
                    CAPTURED_ARRAYS.append(arr.copy())
            except Exception:
                pass
    return _trace


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing or is not a file."
    if os.path.lexists(SUMMARY_PATH):
        os.remove(SUMMARY_PATH)

    old_cwd = os.getcwd()
    old_trace = sys.gettrace()
    np.random.seed(8675309)
    try:
        os.chdir("/home/user")
        sys.settrace(_trace)
        result = runpy.run_path(SCRIPT_PATH, run_name="__main__")
        for value in result.values():
            if isinstance(value, (list, tuple, np.ndarray)):
                try:
                    arr = np.asarray(value, dtype=float)
                    if arr.ndim == 1 and arr.size in (100000, 110000):
                        CAPTURED_ARRAYS.append(arr.copy())
                except Exception:
                    pass
    finally:
        sys.settrace(old_trace)
        os.chdir(old_cwd)

    assert os.path.isfile(SUMMARY_PATH), (
        "Executing mcmc_sampler.py did not create posterior_summary.json"
    )


def _numeric_env(tree):
    env = {}

    def evaluate(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
            return node.value
        if isinstance(node, ast.Name):
            return env.get(node.id)
        if isinstance(node, ast.UnaryOp):
            value = evaluate(node.operand)
            if value is None:
                return None
            if isinstance(node.op, ast.USub):
                return -value
            if isinstance(node.op, ast.UAdd):
                return value
        if isinstance(node, ast.BinOp):
            left, right = evaluate(node.left), evaluate(node.right)
            if left is None or right is None:
                return None
            try:
                if isinstance(node.op, ast.Add): return left + right
                if isinstance(node.op, ast.Sub): return left - right
                if isinstance(node.op, ast.Mult): return left * right
                if isinstance(node.op, ast.Div): return left / right
                if isinstance(node.op, ast.FloorDiv): return left // right
                if isinstance(node.op, ast.Pow): return left ** right
            except Exception:
                return None
        return None

    for _ in range(5):
        for node in ast.walk(tree):
            if isinstance(node, (ast.Assign, ast.AnnAssign)):
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                value_node = node.value
                value = evaluate(value_node)
                if value is not None:
                    for target in targets:
                        if isinstance(target, ast.Name):
                            env[target.id] = value
    return env, evaluate


def _call_name(call):
    parts = []
    node = call.func
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
    return ".".join(reversed(parts))


def test_mcmc_sampler_script_exists():
    """Check that the script mcmc_sampler.py exists."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."


def test_script_contains_required_mh_computation():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as handle:
        source = handle.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)
    env, evaluate = _numeric_env(tree)
    nodes = list(ast.walk(tree))

    loops = [n for n in nodes if isinstance(n, (ast.For, ast.While))]
    assert loops, "The script does not contain an MCMC iteration loop."

    has_110000_loop = False
    for node in loops:
        if isinstance(node, ast.For) and isinstance(node.iter, ast.Call):
            name = _call_name(node.iter)
            if name.endswith("range") and node.iter.args:
                values = [evaluate(arg) for arg in node.iter.args]
                if 110000 in values or (len(values) >= 2 and values[-1] == 110000):
                    has_110000_loop = True
        if isinstance(node, ast.While):
            for child in ast.walk(node.test):
                if evaluate(child) == 110000:
                    has_110000_loop = True
    assert has_110000_loop, "The MCMC loop must run for 110,000 iterations."

    gaussian_ok = False
    random_acceptance = False
    for call in (n for n in nodes if isinstance(n, ast.Call)):
        name = _call_name(call).lower()
        if any(name.endswith(s) for s in ("random", "random_sample", "uniform", "rand")):
            random_acceptance = True
        if name.endswith("normal") or name.endswith("norm.rvs"):
            scale = None
            if len(call.args) >= 2:
                scale = evaluate(call.args[1])
            for kw in call.keywords:
                if kw.arg in ("scale", "sigma"):
                    scale = evaluate(kw.value)
            if scale is not None and math.isclose(float(scale), 0.05, rel_tol=0, abs_tol=1e-12):
                gaussian_ok = True
        if name.endswith("randn") or name.endswith("standard_normal"):
            parent_products = [n for n in nodes if isinstance(n, ast.BinOp) and isinstance(n.op, ast.Mult)]
            if any(evaluate(p.left) == 0.05 or evaluate(p.right) == 0.05 for p in parent_products):
                gaussian_ok = True

    assert gaussian_ok, "No Gaussian proposal with standard deviation 0.05 was found."
    assert random_acceptance, "No random Metropolis-Hastings acceptance draw was found."
    assert any(isinstance(n, ast.If) for n in nodes), "No proposal acceptance/rejection branch was found."

    comparison_values = []
    for node in nodes:
        if isinstance(node, ast.Compare):
            comparison_values.extend(evaluate(x) for x in [node.left] + node.comparators)
    assert 0 in comparison_values and 1 in comparison_values, (
        "The sampler must explicitly reject proposals outside (0, 1)."
    )

    burn_used = False
    for node in nodes:
        if isinstance(node, ast.Subscript) and isinstance(node.slice, ast.Slice):
            if node.slice.lower is not None and evaluate(node.slice.lower) == 10000:
                burn_used = True
        if isinstance(node, ast.Compare):
            if any(evaluate(x) == 10000 for x in [node.left] + node.comparators):
                burn_used = True
    assert burn_used, "The first 10,000 iterations are not discarded as burn-in."

    constants = {n.value for n in nodes if isinstance(n, ast.Constant) and isinstance(n.value, (int, float))}
    assert ({70, 100, 2} <= constants) or ({72, 32} <= constants), (
        "Posterior parameters for the Beta(2,2) prior and 70 heads in 100 flips were not found."
    )
    assert any(isinstance(n, (ast.Assert, ast.Raise)) for n in nodes), (
        "The script must raise AssertionError when validation fails."
    )
    assert any(isinstance(n, ast.Compare) and any(evaluate(x) == 0.005 for x in n.comparators)
               for n in nodes), "The script must enforce a strict 0.005 validation tolerance."


def test_generated_samples_are_real_and_match_summary():
    with open(SUMMARY_PATH, "r", encoding="utf-8") as handle:
        data = json.load(handle)

    valid = []
    for arr in CAPTURED_ARRAYS:
        kept = arr if arr.size == 100000 else arr[-100000:]
        if (np.all(np.isfinite(kept)) and np.all((kept > 0) & (kept < 1))
                and abs(float(np.mean(kept)) - EXPECTED_ANALYTICAL) < 0.005
                and 0.025 < float(np.std(kept)) < 0.070
                and np.unique(kept).size > 1000):
            valid.append(kept)

    assert valid, (
        "Execution did not produce an inspectable chain containing 100,000 nonconstant, "
        "in-bounds posterior samples."
    )
    assert any(abs(float(np.mean(samples)) - float(data["mcmc_mean"])) < 1e-8
               for samples in valid), (
        "The reported mcmc_mean is not the empirical mean of the generated post-burn-in samples."
    )


def test_posterior_summary_exists_and_valid():
    """Check that posterior_summary.json exists and contains the correct values."""
    assert os.path.exists(SUMMARY_PATH), f"Output file {SUMMARY_PATH} is missing."
    assert os.path.isfile(SUMMARY_PATH), f"{SUMMARY_PATH} is not a file."

    with open(SUMMARY_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{SUMMARY_PATH} does not contain valid JSON."

    assert "analytical_mean" in data, "Key 'analytical_mean' is missing from the JSON."
    assert "mcmc_mean" in data, "Key 'mcmc_mean' is missing from the JSON."
    assert "samples_kept" in data, "Key 'samples_kept' is missing from the JSON."
    assert set(data) == {"analytical_mean", "mcmc_mean", "samples_kept"}, (
        "The JSON must have exactly the required three keys."
    )

    assert abs(data["analytical_mean"] - EXPECTED_ANALYTICAL) < 1e-5, \
        f"Analytical mean incorrect: expected approx {EXPECTED_ANALYTICAL:.6f}, got {data['analytical_mean']}"
    assert abs(data["mcmc_mean"] - EXPECTED_ANALYTICAL) < 0.005, \
        f"MCMC mean out of bounds: expected within 0.005 of {EXPECTED_ANALYTICAL:.6f}, got {data['mcmc_mean']}"
    assert abs(data["mcmc_mean"] - data["analytical_mean"]) < 0.005, \
        "MCMC and analytical means must differ by strictly less than 0.005."
    assert data["samples_kept"] == 100000, \
        f"Incorrect number of samples kept: expected 100000, got {data['samples_kept']}"
TEST_EOF

if timeout 180s python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
