#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import os
import signal
import subprocess

import numpy as np
import pytest
from scipy.stats import wasserstein_distance

PARAMS_PATH = "/home/user/best_params.csv"
TEST_PATH = os.path.realpath(__file__)


def test_best_params_exists():
    assert os.path.exists(PARAMS_PATH), f"Output file not found at {PARAMS_PATH}"
    assert os.path.isfile(PARAMS_PATH), f"Path {PARAMS_PATH} is not a file"


def _qualified_calls(tree):
    aliases = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                bound = item.asname or item.name.split('.')[0]
                aliases[bound] = item.name if item.asname else item.name.split('.')[0]
        elif isinstance(node, ast.ImportFrom) and node.module:
            for item in node.names:
                aliases[item.asname or item.name] = f"{node.module}.{item.name}"

    def resolve(node):
        if isinstance(node, ast.Name):
            return aliases.get(node.id, node.id)
        if isinstance(node, ast.Attribute):
            base = resolve(node.value)
            return f"{base}.{node.attr}" if base else node.attr
        return ""

    return [resolve(node.func) for node in ast.walk(tree) if isinstance(node, ast.Call)]


def _is_optimization_script(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            source = handle.read()
        tree = ast.parse(source, filename=path)
    except (OSError, UnicodeError, SyntaxError):
        return False

    calls = _qualified_calls(tree)
    parallel_endings = (
        ".Pool", ".ThreadPool", ".Process", ".ProcessPoolExecutor",
        ".ThreadPoolExecutor", ".Parallel"
    )
    has_parallel = any(
        call.endswith(parallel_endings)
        and call.startswith(("multiprocessing", "concurrent.futures", "joblib"))
        for call in calls
    )
    has_metric = any(
        call == "scipy.stats.wasserstein_distance"
        or call.endswith(".wasserstein_distance")
        for call in calls
    )
    return has_parallel and has_metric


def _candidate_scripts():
    roots = ["/home", "/app", "/workspace", "/workspaces", "/tmp"]
    seen = set()
    for root in roots:
        if not os.path.isdir(root):
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {"__pycache__", ".git", ".cache"}]
            for name in files:
                path = os.path.join(directory, name)
                real = os.path.realpath(path)
                if real == TEST_PATH or real in seen or real == PARAMS_PATH:
                    continue
                seen.add(real)
                try:
                    if os.path.getsize(path) > 2_000_000:
                        continue
                    with open(path, "rb") as handle:
                        first = handle.readline(256).lower()
                except OSError:
                    continue
                if name.endswith(".py") or (first.startswith(b"#!") and b"python" in first):
                    yield path


def _run_script(path):
    process = subprocess.Popen(
        ["python3", path],
        cwd=os.path.dirname(path) or "/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=600)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
        return False, f"timed out after 600 seconds; stderr: {stderr[-1000:]}"
    if process.returncode != 0:
        return False, f"exited with {process.returncode}; stderr: {stderr[-1000:]}"
    if not os.path.isfile(PARAMS_PATH):
        return False, f"completed but did not create {PARAMS_PATH}"
    return True, ""


def test_parallel_optimization_script_is_executable_and_run():
    candidates = [path for path in _candidate_scripts() if _is_optimization_script(path)]
    assert candidates, (
        "No Python optimization script was found that calls both "
        "scipy.stats.wasserstein_distance and a multiprocessing/concurrent parallel API"
    )

    errors = []
    for path in candidates:
        try:
            if os.path.lexists(PARAMS_PATH):
                os.unlink(PARAMS_PATH)
        except OSError as exc:
            pytest.fail(f"Could not clear old output before executing {path}: {exc}")
        ok, error = _run_script(path)
        if ok:
            return
        errors.append(f"{path}: {error}")

    pytest.fail("No parallel optimization script successfully regenerated the output. " + " | ".join(errors))


def test_wasserstein_distance_metric():
    assert os.path.exists(PARAMS_PATH), f"Output file not found at {PARAMS_PATH}"

    with open(PARAMS_PATH, "r") as f:
        content = f.read().strip()

    try:
        params = content.split(',')
        assert len(params) == 3, f"Expected 3 comma-separated values, found {len(params)}"
        alpha_s, beta_s, gamma_s = (item.strip() for item in params)
        alpha, beta, gamma = map(float, (alpha_s, beta_s, gamma_s))
        assert all(math.isfinite(value) for value in (alpha, beta, gamma)), "All parameters must be finite"
        assert all(0.0 <= value <= 10.0 for value in (alpha, beta, gamma)), "All parameters must be within [0.0, 10.0]"
    except Exception as e:
        pytest.fail(f"Failed to parse {PARAMS_PATH}. Ensure it contains exactly 3 finite, in-range comma-separated floats. Error: {e}")

    exp_data_path = "/app/data/experimental_spectrum.txt"
    assert os.path.exists(exp_data_path), f"Experimental data missing at {exp_data_path}"
    exp_data = np.loadtxt(exp_data_path)
    assert exp_data.size == 1024, f"Experimental data did not contain 1024 values. Found {exp_data.size}."
    assert np.all(np.isfinite(exp_data)), "Experimental data contains non-finite values"

    binary_path = "/app/bin/spectral_sim"
    assert os.path.exists(binary_path), f"Binary missing at {binary_path}"

    result = subprocess.run([binary_path, alpha_s, beta_s, gamma_s], capture_output=True, text=True)
    assert result.returncode == 0, f"Binary execution failed with return code {result.returncode}. Stderr: {result.stderr}"

    sim_data = np.fromstring(result.stdout, sep=' ')
    assert len(sim_data) == 1024, f"Binary output did not contain 1024 values. Found {len(sim_data)}."
    assert np.all(np.isfinite(sim_data)), "Binary output contains non-finite values"

    metric_value = wasserstein_distance(exp_data, sim_data)
    assert math.isfinite(metric_value), "Wasserstein distance is non-finite"
    assert metric_value <= 0.15, f"Wasserstein distance {metric_value:.5f} is not <= 0.15. Parameters: alpha={alpha_s}, beta={beta_s}, gamma={gamma_s}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
