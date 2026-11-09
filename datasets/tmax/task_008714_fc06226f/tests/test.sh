#!/bin/bash
set -e
mkdir -p /logs/verifier

NOTEBOOK=/home/user/heat_sim.ipynb
RESULTS=/home/user/sim_results.json

# The results must be produced by a fresh, successful execution of the submitted notebook.
rm -f "$RESULTS"
if ! timeout 180s jupyter nbconvert --to notebook --execute --inplace \
    --ExecutePreprocessor.timeout=120 "$NOTEBOOK" >/tmp/heat_sim_nbconvert.log 2>&1; then
    cat /tmp/heat_sim_nbconvert.log
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os

import numpy as np
import pytest


def test_notebook_exists():
    """Test that the Jupyter notebook was created."""
    notebook_path = "/home/user/heat_sim.ipynb"
    assert os.path.exists(notebook_path), f"Jupyter notebook {notebook_path} was not created."


def test_notebook_is_executed_simulation():
    """Require an executed notebook containing a credible NumPy Euler simulation."""
    notebook_path = "/home/user/heat_sim.ipynb"
    with open(notebook_path, "r", encoding="utf-8") as f:
        notebook = json.load(f)

    assert notebook.get("nbformat") == 4, "Submission is not a valid version 4 Jupyter notebook."
    code_cells = [
        cell for cell in notebook.get("cells", [])
        if cell.get("cell_type") == "code" and "".join(cell.get("source", [])).strip()
    ]
    assert code_cells, "Notebook contains no executable code."
    assert all(cell.get("execution_count") is not None for cell in code_cells), \
        "Notebook was not fully executed."

    source = "\n".join("".join(cell.get("source", [])) for cell in code_cells)
    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        pytest.fail(f"Notebook code is not valid Python: {exc}")

    imports_numpy = any(
        (isinstance(node, ast.Import) and any(alias.name == "numpy" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "numpy")
        for node in ast.walk(tree)
    )
    assert imports_numpy, "Notebook must implement the simulation using numpy."

    calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                calls.append(node.func.id)
            elif isinstance(node.func, ast.Attribute):
                calls.append(node.func.attr)

    assert "ceil" in calls, "The number of time steps must be calculated with math.ceil."
    assert any(name in calls for name in ("zeros", "zeros_like", "empty", "full")), \
        "Notebook does not construct a NumPy simulation grid."
    assert any(isinstance(node, (ast.For, ast.While)) for node in ast.walk(tree)), \
        "Notebook does not perform the required explicit time stepping."
    assert any(
        isinstance(node, ast.Subscript) and isinstance(node.ctx, ast.Store)
        for node in ast.walk(tree)
    ), "Notebook does not update a multidimensional array."
    assert any(
        isinstance(node, ast.Subscript) and isinstance(node.slice, ast.Tuple)
        for node in ast.walk(tree)
    ), "Notebook does not use multidimensional array indexing."
    assert any(isinstance(node, ast.Compare) for node in ast.walk(tree)), \
        "Notebook does not construct the spatially bounded heat source."
    assert "dump" in calls, "Notebook does not export its computed results as JSON."
    assert "/home/user/sim_results.json" in source, "Notebook writes results to the wrong path."

    # The final temperatures are not supplied by the task and must not simply be embedded.
    numeric_literals = [
        float(node.value) for node in ast.walk(tree)
        if isinstance(node, ast.Constant)
        and isinstance(node.value, (int, float))
        and not isinstance(node.value, bool)
    ]
    forbidden = (4.811568285918235, 4.887293521035074)
    for expected in forbidden:
        assert not any(math.isclose(value, expected, rel_tol=1e-12, abs_tol=1e-12)
                       for value in numeric_literals), \
            "Notebook embeds a final answer instead of computing the simulation."


def reference_simulation(N):
    alpha = 0.05
    dx = dy = 1.0 / N
    dt_max = (dx * dx * dy * dy) / (2.0 * alpha * (dx * dx + dy * dy))
    dt = 0.8 * dt_max
    M = math.ceil(0.1 / dt)

    coords = np.arange(N + 1, dtype=float) * dx
    x, y = np.meshgrid(coords, coords, indexing="ij")
    Q = np.where(
        (x >= 0.4) & (x <= 0.6) & (y >= 0.4) & (y <= 0.6),
        50.0,
        0.0,
    )
    T = np.zeros((N + 1, N + 1), dtype=float)
    for _ in range(M):
        old = T.copy()
        T[1:-1, 1:-1] = (
            old[1:-1, 1:-1]
            + alpha * dt * (
                (old[2:, 1:-1] - 2.0 * old[1:-1, 1:-1] + old[:-2, 1:-1]) / dx**2
                + (old[1:-1, 2:] - 2.0 * old[1:-1, 1:-1] + old[1:-1, :-2]) / dy**2
            )
            + dt * Q[1:-1, 1:-1]
        )
        T[0, :] = T[-1, :] = T[:, 0] = T[:, -1] = 0.0
    return dt_max, float(T[N // 2, N // 2])


def test_json_output():
    """Test that the JSON results file is created and contains the correct values."""
    json_path = "/home/user/sim_results.json"
    assert os.path.exists(json_path), f"Results file {json_path} was not created."

    with open(json_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} is not a valid JSON file.")

    expected_keys = {"dt_max_N20", "dt_max_N40", "T_center_N20", "T_center_N40"}
    assert set(results.keys()) == expected_keys, f"JSON file must contain exactly keys: {expected_keys}"

    # Expected values derived from the problem statement
    expected_dt_max_20 = 0.0125
    expected_dt_max_40 = 0.003125
    expected_T_c_20 = 4.811568285918235
    expected_T_c_40 = 4.887293521035074

    assert math.isclose(results["dt_max_N20"], expected_dt_max_20, rel_tol=1e-5), \
        f"dt_max_N20 is incorrect. Expected {expected_dt_max_20}, got {results['dt_max_N20']}"

    assert math.isclose(results["dt_max_N40"], expected_dt_max_40, rel_tol=1e-5), \
        f"dt_max_N40 is incorrect. Expected {expected_dt_max_40}, got {results['dt_max_N40']}"

    assert math.isclose(results["T_center_N20"], expected_T_c_20, rel_tol=1e-5), \
        f"T_center_N20 is incorrect. Expected {expected_T_c_20}, got {results['T_center_N20']}"

    assert math.isclose(results["T_center_N40"], expected_T_c_40, rel_tol=1e-5), \
        f"T_center_N40 is incorrect. Expected {expected_T_c_40}, got {results['T_center_N40']}"

    # Also derive the answers independently rather than relying only on constants.
    ref20 = reference_simulation(20)
    ref40 = reference_simulation(40)
    derived = {
        "dt_max_N20": ref20[0],
        "dt_max_N40": ref40[0],
        "T_center_N20": ref20[1],
        "T_center_N40": ref40[1],
    }
    for key, expected in derived.items():
        assert isinstance(results[key], (int, float)) and not isinstance(results[key], bool)
        assert math.isfinite(float(results[key]))
        assert math.isclose(float(results[key]), expected, rel_tol=1e-9, abs_tol=1e-12), \
            f"{key} differs from the independently executed reference simulation."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
