#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import subprocess
import sys
import time

import numpy as np
import pytest

SCRIPT_PATH = '/home/user/analyze_signal.py'
RESULT_PATH = '/home/user/result.txt'


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing."
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)

    start = time.perf_counter()
    completed = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=1.5,
    )
    elapsed = time.perf_counter() - start
    assert completed.returncode == 0, (
        f"The script failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert elapsed < 1.0, f"The optimized script took {elapsed:.3f} seconds; expected less than 1 second."
    assert os.path.isfile(RESULT_PATH), "Running the script did not generate /home/user/result.txt."


def load_submission():
    spec = importlib.util.spec_from_file_location('submitted_analyze_signal', SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def original_computation(data, x_grid, bandwidth):
    density = np.zeros(len(x_grid))
    for i, x in enumerate(x_grid):
        for d in data:
            density[i] += np.exp(-0.5 * ((x - d) / bandwidth) ** 2)
    return density / (len(data) * bandwidth * np.sqrt(2 * np.pi))


def test_result_file_exists_and_correct():
    result_path = '/home/user/result.txt'
    assert os.path.isfile(result_path), f"The output file {result_path} does not exist. Did you run the script?"

    with open(result_path, 'r') as f:
        result = f.read().strip()

    assert result == "5.0250", f"Expected result '5.0250', but got '{result}'. Check your vectorization logic."


def test_script_is_vectorized():
    script_path = '/home/user/analyze_signal.py'
    assert os.path.isfile(script_path), f"The script {script_path} is missing."

    with open(script_path, 'r') as f:
        code = f.read()

    assert "for d in data:" not in code, "The nested loop 'for d in data:' was found. The function must be fully vectorized."
    assert "for i, x in enumerate(x_grid):" not in code, "The loop over x_grid was found. The function must be fully vectorized."

    tree = ast.parse(code, filename=script_path)
    functions = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == 'slow_density_estimation']
    assert len(functions) == 1, "Expected exactly one top-level slow_density_estimation function."
    forbidden = (ast.For, ast.AsyncFor, ast.While, ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp)
    assert not any(isinstance(n, forbidden) for n in ast.walk(functions[0])), (
        "slow_density_estimation must use fully vectorized operations, not loops or comprehensions."
    )


def test_density_matches_original_computation():
    module = load_submission()
    assert callable(getattr(module, 'slow_density_estimation', None)), "slow_density_estimation is missing or not callable."

    rng = np.random.default_rng(918273)
    cases = [
        (rng.normal(-0.3, 1.7, 17), np.linspace(-3.2, 2.6, 23), 0.13),
        (rng.uniform(-8.0, 4.0, 31), rng.uniform(-9.0, 5.0, 19), 0.47),
        (np.array([-2.0, -0.1, 0.0, 1.3, 4.2]), np.array([4.2, -1.5, 0.25]), 1.1),
    ]
    for data, grid, bandwidth in cases:
        data_before = data.copy()
        grid_before = grid.copy()
        expected = original_computation(data, grid, bandwidth)
        actual = np.asarray(module.slow_density_estimation(data, grid, bandwidth=bandwidth))
        assert actual.shape == expected.shape, f"Expected output shape {expected.shape}, got {actual.shape}."
        np.testing.assert_allclose(actual, expected, rtol=1e-12, atol=1e-14)
        np.testing.assert_array_equal(data, data_before, err_msg="The function modified its data input.")
        np.testing.assert_array_equal(grid, grid_before, err_msg="The function modified its x_grid input.")


def test_density_estimation_is_significantly_faster_than_original():
    module = load_submission()
    rng = np.random.default_rng(24680)
    data = rng.normal(size=600)
    grid = np.linspace(-3.5, 3.5, 220)
    bandwidth = 0.19

    start = time.perf_counter()
    expected = original_computation(data, grid, bandwidth)
    original_time = time.perf_counter() - start

    start = time.perf_counter()
    actual = np.asarray(module.slow_density_estimation(data, grid, bandwidth=bandwidth))
    optimized_time = time.perf_counter() - start

    np.testing.assert_allclose(actual, expected, rtol=1e-12, atol=1e-14)
    assert optimized_time < original_time * 0.4, (
        f"Density estimation was not significantly faster: optimized={optimized_time:.4f}s, "
        f"original={original_time:.4f}s."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
