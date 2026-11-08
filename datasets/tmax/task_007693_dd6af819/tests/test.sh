#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import secrets
import subprocess
import sys

import pytest

VENV_PYTHON = "/home/user/venv/bin/python"
VENV_PYTEST = "/home/user/venv/bin/pytest"
VENV_PAPERMILL = "/home/user/venv/bin/papermill"
WORKSPACE = "/home/user/workspace"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 180)
    return subprocess.run(cmd, **kwargs)


def reference_distances(np, num_steps, num_trials, seed):
    rng = np.random.default_rng(seed)
    angles = rng.uniform(0, 2 * np.pi, size=(num_trials, num_steps))
    x = np.sum(np.cos(angles), axis=1)
    y = np.sum(np.sin(angles), axis=1)
    return np.sqrt(x ** 2 + y ** 2)


def expected_ks_text(np, stats, num_steps, num_trials, seed):
    distances = reference_distances(np, num_steps, num_trials, seed)
    statistic, pvalue = stats.kstest(
        distances,
        "rayleigh",
        args=(),
        kwds={"scale": np.sqrt(num_steps / 2.0)},
    )
    return f"{statistic:.6f},{pvalue:.6f}"


def test_venv_and_packages():
    assert os.path.exists(VENV_PYTHON), f"Virtual environment Python not found at {VENV_PYTHON}"

    packages = ["numpy", "scipy", "pytest", "jupyter", "nbformat", "papermill"]
    for pkg in packages:
        result = run([VENV_PYTHON, "-c", f"import {pkg}"])
        assert result.returncode == 0, (
            f"Package {pkg} is not installed in the virtual environment. "
            f"Error: {result.stderr}"
        )


def test_workspace_files_exist():
    expected_files = [
        "mc_sim.py",
        "test_sim.py",
        "create_nb.py",
        "experiment.ipynb",
        "output.ipynb",
        "ks_result.txt",
    ]
    for f in expected_files:
        path = os.path.join(WORKSPACE, f)
        assert os.path.exists(path), f"Expected file {path} does not exist"
        assert os.path.isfile(path), f"Expected {path} to be a regular file"


def test_simulation_implementation_on_derived_inputs():
    import numpy as np

    # Derive fresh cases at verification time so a single precomputed result cannot pass.
    cases = []
    for _ in range(3):
        num_steps = 3 + secrets.randbelow(35)
        num_trials = 17 + secrets.randbelow(90)
        seed = secrets.randbits(31)
        expected = reference_distances(np, num_steps, num_trials, seed)
        cases.append((num_steps, num_trials, seed, expected))

    module_path = os.path.join(WORKSPACE, "mc_sim.py")
    spec = importlib.util.spec_from_file_location("submitted_mc_sim", module_path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "simulate_random_walk", None)), (
        "mc_sim.py must define simulate_random_walk"
    )

    for num_steps, num_trials, seed, expected in cases:
        actual = module.simulate_random_walk(num_steps, num_trials, seed)
        assert isinstance(actual, np.ndarray), "simulate_random_walk must return a numpy array"
        assert actual.shape == (num_trials,), "Returned array must have length num_trials"
        np.testing.assert_allclose(actual, expected, rtol=1e-12, atol=1e-12)


def test_required_regression_test_is_present():
    test_file = os.path.join(WORKSPACE, "test_sim.py")
    with open(test_file, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=test_file)
    funcs = [
        n for n in tree.body
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
        and n.name == "test_mean_distance"
    ]
    assert funcs, "test_sim.py must define test_mean_distance()"
    fn = funcs[0]
    assert any(isinstance(n, ast.Assert) for n in ast.walk(fn)), (
        "test_mean_distance() must contain an assertion"
    )
    calls = [n for n in ast.walk(fn) if isinstance(n, ast.Call)]
    required_call = False
    for call in calls:
        name = call.func.id if isinstance(call.func, ast.Name) else (
            call.func.attr if isinstance(call.func, ast.Attribute) else None
        )
        values = [a.value for a in call.args if isinstance(a, ast.Constant)]
        if name == "simulate_random_walk" and values[:3] == [100, 10000, 42]:
            required_call = True
            break
    assert required_call, (
        "test_mean_distance() must call simulate_random_walk(100, 10000, 42)"
    )
    constants = [n.value for n in ast.walk(fn) if isinstance(n, ast.Constant)]
    assert any(isinstance(v, (int, float)) and abs(v - 0.1) < 1e-12 for v in constants), (
        "test_mean_distance() must use the required 0.1 tolerance"
    )


def test_test_sim_passes():
    test_file = os.path.join(WORKSPACE, "test_sim.py")
    assert os.path.exists(VENV_PYTEST), f"pytest not found at {VENV_PYTEST}"

    result = run([VENV_PYTEST, test_file])
    assert result.returncode == 0, (
        f"pytest on {test_file} failed:\n{result.stdout}\n{result.stderr}"
    )


def test_create_and_execute_notebook_workflow():
    import nbformat
    import numpy as np
    import scipy.stats as stats

    create_path = os.path.join(WORKSPACE, "create_nb.py")
    with open(create_path, "r", encoding="utf-8") as f:
        create_source = f.read()
    create_tree = ast.parse(create_source, filename=create_path)
    imports_nbformat = any(
        (isinstance(n, ast.Import) and any(a.name == "nbformat" for a in n.names))
        or (isinstance(n, ast.ImportFrom) and n.module == "nbformat")
        for n in ast.walk(create_tree)
    )
    assert imports_nbformat, "create_nb.py must use nbformat"

    experiment = os.path.join(WORKSPACE, "experiment.ipynb")
    output = os.path.join(WORKSPACE, "output.ipynb")
    ks_path = os.path.join(WORKSPACE, "ks_result.txt")
    for path in (experiment, output, ks_path):
        if os.path.exists(path):
            os.remove(path)

    result = run([VENV_PYTHON, create_path], cwd=WORKSPACE)
    assert result.returncode == 0, (
        f"create_nb.py failed:\n{result.stdout}\n{result.stderr}"
    )
    assert os.path.isfile(experiment), "create_nb.py did not generate experiment.ipynb"

    notebook = nbformat.read(experiment, as_version=4)
    assert len(notebook.cells) == 2, "experiment.ipynb must contain exactly two cells"
    assert all(cell.cell_type == "code" for cell in notebook.cells), (
        "Both notebook cells must be code cells"
    )
    assert "parameters" in notebook.cells[0].metadata.get("tags", []), (
        "The first cell must have the parameters tag"
    )

    parameter_tree = ast.parse(notebook.cells[0].source)
    defaults = {}
    for node in parameter_tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1:
            target = node.targets[0]
            if isinstance(target, ast.Name) and isinstance(node.value, ast.Constant):
                defaults[target.id] = node.value.value
    assert defaults.get("num_steps") == 10
    assert defaults.get("num_trials") == 100
    assert defaults.get("seed") == 42

    second_source = notebook.cells[1].source
    second_tree = ast.parse(second_source)
    imported_sim = any(
        isinstance(n, ast.ImportFrom)
        and n.module == "mc_sim"
        and any(a.name == "simulate_random_walk" for a in n.names)
        for n in ast.walk(second_tree)
    )
    assert imported_sim, "Second cell must import simulate_random_walk from mc_sim"
    assert "kstest" in second_source and "rayleigh" in second_source
    assert "ks_result.txt" in second_source

    assert os.path.exists(VENV_PAPERMILL), f"papermill not found at {VENV_PAPERMILL}"

    # Exercise the generated notebook with fresh parameters and independently derive the answer.
    dynamic_steps = 12 + secrets.randbelow(25)
    dynamic_trials = 350 + secrets.randbelow(350)
    dynamic_seed = secrets.randbits(30)
    dynamic_expected = expected_ks_text(
        np, stats, dynamic_steps, dynamic_trials, dynamic_seed
    )
    dynamic_output = os.path.join(WORKSPACE, ".verifier_dynamic_output.ipynb")
    if os.path.exists(dynamic_output):
        os.remove(dynamic_output)
    result = run([
        VENV_PAPERMILL,
        experiment,
        dynamic_output,
        "-p", "num_steps", str(dynamic_steps),
        "-p", "num_trials", str(dynamic_trials),
        "-p", "seed", str(dynamic_seed),
    ], cwd=WORKSPACE)
    assert result.returncode == 0, (
        f"Dynamic papermill execution failed:\n{result.stdout}\n{result.stderr}"
    )
    with open(ks_path, "r", encoding="utf-8") as f:
        assert f.read().strip() == dynamic_expected

    dynamic_nb = nbformat.read(dynamic_output, as_version=4)
    assert not any(
        output_item.get("output_type") == "error"
        for cell in dynamic_nb.cells if cell.cell_type == "code"
        for output_item in cell.get("outputs", [])
    ), "Dynamic output notebook contains an execution error"

    # Perform the exact execution requested by the instruction, leaving output.ipynb
    # and ks_result.txt in their required final state.
    result = run([
        VENV_PAPERMILL,
        experiment,
        output,
        "-p", "num_steps", "200",
        "-p", "num_trials", "25000",
        "-p", "seed", "1001",
    ], cwd=WORKSPACE)
    assert result.returncode == 0, (
        f"Required papermill execution failed:\n{result.stdout}\n{result.stderr}"
    )
    assert os.path.isfile(output), "papermill did not create output.ipynb"
    executed = nbformat.read(output, as_version=4)
    assert any(
        cell.cell_type == "code" and cell.get("execution_count") is not None
        for cell in executed.cells
    ), "output.ipynb is not an executed notebook"
    assert not any(
        output_item.get("output_type") == "error"
        for cell in executed.cells if cell.cell_type == "code"
        for output_item in cell.get("outputs", [])
    ), "output.ipynb contains an execution error"


def test_ks_result_content():
    ks_result_path = os.path.join(WORKSPACE, "ks_result.txt")
    assert os.path.exists(ks_result_path), f"{ks_result_path} does not exist"

    with open(ks_result_path, "r") as f:
        actual_content = f.read().strip()

    # Compute the golden value using the venv's python to ensure exact floating-point matching
    compute_script = """
import numpy as np
import scipy.stats as stats

num_steps = 200
num_trials = 25000
seed = 1001

rng = np.random.default_rng(seed)
angles = rng.uniform(0, 2*np.pi, size=(num_trials, num_steps))
x = np.sum(np.cos(angles), axis=1)
y = np.sum(np.sin(angles), axis=1)
distances = np.sqrt(x**2 + y**2)

scale = np.sqrt(num_steps / 2.0)
statistic, pvalue = stats.kstest(distances, 'rayleigh', args=(), kwds={'scale': scale})

print(f"{statistic:.6f},{pvalue:.6f}")
"""
    result = run([VENV_PYTHON, "-c", compute_script])
    assert result.returncode == 0, f"Failed to compute golden value: {result.stderr}"

    expected_content = result.stdout.strip()
    assert actual_content == expected_content, (
        f"Content of ks_result.txt ({actual_content}) does not match "
        f"expected ({expected_content})"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
