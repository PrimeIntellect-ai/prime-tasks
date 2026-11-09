#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import math
import os
from pathlib import Path

import nbformat
import numpy as np
from nbconvert.preprocessors import ExecutePreprocessor

PROJECT = Path("/home/user/sim_project")
OPTIMIZER = PROJECT / "optimizer.py"
NOTEBOOK = PROJECT / "simulation.ipynb"
RESULTS = PROJECT / "results.csv"

ORIGINAL_OPTIMIZER = '''import numpy as np

def gauss_newton(X, y, initial_guess, max_iter=50, tol=1e-5):
    beta = np.array(initial_guess, dtype=float)
    for i in range(max_iter):
        # Model: y = beta[0]*X[:,0] + beta[1]*X[:,1] + beta[2]*(X[:,0]**2)
        y_pred = beta[0] * X[:, 0] + beta[1] * X[:, 1] + beta[2] * (X[:, 0]**2)

        # Jacobian matrix
        J = np.column_stack([
            X[:, 0],
            X[:, 1],
            X[:, 0]**2
        ])

        r = y - y_pred

        JTJ = J.T @ J
        JTr = J.T @ r

        # This standard inversion fails due to collinearity
        delta = np.linalg.inv(JTJ) @ JTr

        beta += delta
        if np.linalg.norm(delta) < tol:
            break
    return beta'''

EXPECTED_NOTEBOOK_SOURCE = '''import numpy as np
from optimizer import gauss_newton

np.random.seed(42)
N = 100
# Create collinear features (near-singular)
X0 = np.linspace(0, 10, N)
X1 = X0 + np.random.normal(0, 1e-10, size=N)

X = np.column_stack([X0, X1])

# True parameters: beta = [1.5, 0.0, 0.5]
y_true = 1.5 * X[:, 0] + 0.5 * (X[:, 0]**2)
y = y_true + np.random.normal(0, 0.1, size=N)

# Initial guess
beta_init = [0.1, 0.1, 0.1]

# Run optimizer
beta_opt = gauss_newton(X, y, beta_init)

# Save results
np.savetxt("results.csv", beta_opt.reshape(1, -1), delimiter=",", fmt="%.6f")
print("Optimization successful. Results saved to results.csv")'''


def load_optimizer():
    spec = importlib.util.spec_from_file_location("submitted_optimizer", OPTIMIZER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_optimizer_was_modified_and_is_importable():
    assert OPTIMIZER.is_file(), f"Missing {OPTIMIZER}"
    source = OPTIMIZER.read_text()
    assert source.strip() != ORIGINAL_OPTIMIZER.strip(), "optimizer.py was not modified."
    module = load_optimizer()
    assert callable(getattr(module, "gauss_newton", None)), "gauss_newton is missing or not callable."


def test_optimizer_handles_singular_designs():
    module = load_optimizer()

    # Answers are generated here rather than read from results.csv. In each case
    # X[:, 1] exactly duplicates X[:, 0], so the original inverse must fail while
    # a robust pseudo-inverse or regularized solve must still fit the model.
    cases = [
        (np.linspace(-3.0, 4.0, 81), np.array([0.2, -0.7, 0.4]), np.array([1.3, 0.0, -0.25])),
        (np.random.default_rng(731).uniform(-2.5, 3.5, 127), np.array([-2.0, 1.0, 3.0]), np.array([-0.4, 0.0, 0.8])),
    ]

    for x0, initial, generating_beta in cases:
        X = np.column_stack([x0, x0])
        y = (generating_beta[0] + generating_beta[1]) * x0 + generating_beta[2] * x0**2
        beta = np.asarray(module.gauss_newton(X, y, initial), dtype=float)
        assert beta.shape == (3,), f"Expected three parameters, got shape {beta.shape}."
        assert np.all(np.isfinite(beta)), f"Optimizer returned non-finite parameters: {beta}"
        prediction = beta[0] * X[:, 0] + beta[1] * X[:, 1] + beta[2] * X[:, 0]**2
        error = np.linalg.norm(prediction - y)
        assert error <= 1e-4 * max(1.0, np.linalg.norm(y)), (
            f"Optimizer did not solve an exactly singular design; prediction error was {error}."
        )


def test_notebook_is_original_workflow_and_executes_headlessly():
    assert NOTEBOOK.is_file(), f"Missing {NOTEBOOK}"
    nb = nbformat.read(str(NOTEBOOK), as_version=4)
    assert len(nb.cells) == 1 and nb.cells[0].cell_type == "code", (
        "simulation.ipynb must retain the supplied simulation workflow."
    )
    assert nb.cells[0].source.strip() == EXPECTED_NOTEBOOK_SOURCE.strip(), (
        "The notebook's random seed or data-generation/execution logic was changed."
    )

    # Remove any precomputed or hand-written answer and require the actual notebook
    # to recreate it in a fresh Jupyter kernel.
    if RESULTS.exists():
        RESULTS.unlink()
    executor = ExecutePreprocessor(timeout=180, kernel_name="python3")
    executor.preprocess(nb, {"metadata": {"path": str(PROJECT)}})
    nbformat.write(nb, "/tmp/executed_simulation.ipynb")
    assert RESULTS.is_file(), "Notebook completed without generating results.csv."


def test_results_file_exists():
    results_path = "/home/user/sim_project/results.csv"
    assert os.path.isfile(results_path), f"File {results_path} does not exist. Ensure the notebook was executed successfully."


def test_results_content():
    results_path = "/home/user/sim_project/results.csv"
    assert os.path.isfile(results_path), "Results file missing."

    with open(results_path, 'r') as f:
        content = f.read().strip()

    assert content, f"File {results_path} is empty."

    parts = content.split(',')
    assert len(parts) == 3, f"Expected exactly 3 comma-separated values in {results_path}, but got {len(parts)}."

    try:
        results = [float(x) for x in parts]
    except ValueError:
        assert False, f"Could not parse values in {results_path} as floats. Content: {content}"

    expected = [0.749558, 0.749558, 0.500057]

    for i, (res, exp) in enumerate(zip(results, expected)):
        assert math.isclose(res, exp, abs_tol=1e-2), (
            f"Estimated parameter at index {i} is {res}, expected approximately {exp} "
            "(tolerance 1e-2). Ensure you are handling collinearity properly."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
