#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import ast
import math
import os
import shutil
import subprocess
import tempfile
import uuid

VENV_PYTHON = "/home/user/venv/bin/python"
SCRIPT = "/home/user/run_experiment.py"
TRACKING_DIR = "/home/user/mlruns"
TRACKING_URI = "file:///home/user/mlruns"

assert os.path.exists(VENV_PYTHON), f"Virtual environment python binary not found at {VENV_PYTHON}"
assert os.path.isfile(SCRIPT), f"The script {SCRIPT} does not exist or is not a regular file"

# Inspect the demanded implementation without replacing behavioral validation.
with open(SCRIPT, "r", encoding="utf-8") as f:
    source = f.read()
tree = ast.parse(source, filename=SCRIPT)

for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        assert all(not alias.name.startswith("sklearn") for alias in node.names), "PCA script must not import sklearn"
    elif isinstance(node, ast.ImportFrom):
        assert not (node.module or "").startswith("sklearn"), "PCA script must not import sklearn"


def call_leaf(call):
    fn = call.func
    if isinstance(fn, ast.Name):
        return fn.id
    if isinstance(fn, ast.Attribute):
        return fn.attr
    return None

assert any(isinstance(n, ast.Call) and call_leaf(n) == "svd" for n in ast.walk(tree)), \
    "run_experiment.py must call numpy.linalg.svd"

constants = {}

def const_int(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, int):
        return node.value
    if isinstance(node, ast.Name):
        return constants.get(node.id)
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
        value = const_int(node.operand)
        return None if value is None else -value
    if isinstance(node, ast.BinOp):
        left, right = const_int(node.left), const_int(node.right)
        if left is None or right is None:
            return None
        try:
            if isinstance(node.op, ast.Add): return left + right
            if isinstance(node.op, ast.Sub): return left - right
            if isinstance(node.op, ast.Mult): return left * right
            if isinstance(node.op, ast.Pow): return left ** right
            if isinstance(node.op, ast.FloorDiv): return left // right
        except Exception:
            return None
    return None

for node in tree.body:
    if isinstance(node, (ast.Assign, ast.AnnAssign)):
        value_node = node.value
        value = const_int(value_node)
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        if value is not None:
            for target in targets:
                if isinstance(target, ast.Name):
                    constants[target.id] = value


def is_projection_op(node):
    return isinstance(node, ast.BinOp) and isinstance(node.op, ast.MatMult) or (
        isinstance(node, ast.Call) and call_leaf(node) in {"dot", "matmul"}
    )

operation_functions = set()
for node in ast.walk(tree):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and any(is_projection_op(x) for x in ast.walk(node)):
        operation_functions.add(node.name)

benchmark_loop_found = False
for node in ast.walk(tree):
    if not isinstance(node, ast.For) or not isinstance(node.iter, ast.Call) or call_leaf(node.iter) != "range":
        continue
    values = [const_int(arg) for arg in node.iter.args]
    if any(v is None for v in values):
        continue
    try:
        iterations = len(range(*values))
    except Exception:
        continue
    body_has_projection = any(is_projection_op(x) for stmt in node.body for x in ast.walk(stmt))
    body_calls_projection = any(
        isinstance(x, ast.Call) and isinstance(x.func, ast.Name) and x.func.id in operation_functions
        for stmt in node.body for x in ast.walk(stmt)
    )
    if iterations == 1000 and (body_has_projection or body_calls_projection):
        benchmark_loop_found = True
        break
assert benchmark_loop_found, "No 1000-iteration projection matrix-multiplication benchmark loop was found"

import mlflow
import numpy as np

X = np.loadtxt("/home/user/data/matrix.csv", delimiter=",")
assert X.ndim == 2
X_centered = X - X.mean(axis=0)
_, _, expected_vt = np.linalg.svd(X_centered, full_matrices=False)


def verify_tracking_state(expected_count=3):
    mlflow.set_tracking_uri(TRACKING_URI)
    experiment = mlflow.get_experiment_by_name("PCA_Benchmarking")
    assert experiment is not None, "Experiment 'PCA_Benchmarking' not found"

    runs = mlflow.search_runs(experiment_ids=[experiment.experiment_id])
    assert len(runs) == expected_count, f"Expected {expected_count} runs, found {len(runs)}"

    expected_ks = {"2", "5", "10"}
    assert "params.k" in runs.columns, "Missing k parameter"
    actual_ks = set(runs["params.k"].dropna().astype(str).tolist())
    assert actual_ks == expected_ks, f"Expected runs for k in {expected_ks}, got {actual_ks}"

    for _, run in runs.iterrows():
        k = int(run["params.k"])
        mse = float(run["metrics.mse"])
        avg_time = float(run["metrics.avg_inference_time_sec"])
        assert math.isfinite(mse), f"Missing or non-finite mse for k={k}"
        assert math.isfinite(avg_time) and avg_time > 0, f"Invalid average inference time for k={k}: {avg_time}"

        artifact_uri = str(run["artifact_uri"]).replace("file://", "")
        artifact_path = os.path.join(artifact_uri, "projection_matrix.npy")
        assert os.path.exists(artifact_path), f"Artifact projection_matrix.npy not found for k={k} at {artifact_path}"

        W = np.load(artifact_path, allow_pickle=False)
        assert W.shape == (X.shape[1], k), f"Expected projection matrix shape {(X.shape[1], k)}, got {W.shape}"
        assert np.issubdtype(W.dtype, np.number) and np.isfinite(W).all(), f"Projection matrix for k={k} is not finite numeric data"

        expected_W = expected_vt[:k].T
        assert np.allclose(W.T @ W, np.eye(k), rtol=1e-5, atol=1e-6), f"Projection matrix for k={k} is not orthonormal"
        assert np.allclose(W @ W.T, expected_W @ expected_W.T, rtol=1e-5, atol=1e-6), \
            f"Projection matrix for k={k} is not the top-k PCA subspace"

        reconstructed = (X_centered @ W) @ W.T + X.mean(axis=0)
        expected_mse = float(np.mean((X - reconstructed) ** 2))
        assert np.isclose(mse, expected_mse, rtol=1e-6, atol=1e-9), \
            f"Incorrect mse for k={k}: logged {mse}, recomputed {expected_mse}"

# Preserve all original final-state checks, strengthened with numerical validation.
verify_tracking_state()

# Execute the submitted artifact against the real dataset in a fresh tracking store.
backup = f"/home/user/.mlruns_verifier_backup_{uuid.uuid4().hex}"
workdir = tempfile.mkdtemp(prefix="pca_verifier_")
os.replace(TRACKING_DIR, backup)
try:
    for k in (2, 5, 10):
        result = subprocess.run(
            [VENV_PYTHON, SCRIPT, str(k)],
            cwd=workdir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, \
            f"run_experiment.py failed for k={k}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    verify_tracking_state()
finally:
    if os.path.lexists(TRACKING_DIR):
        if os.path.isdir(TRACKING_DIR) and not os.path.islink(TRACKING_DIR):
            shutil.rmtree(TRACKING_DIR)
        else:
            os.unlink(TRACKING_DIR)
    os.replace(backup, TRACKING_DIR)
    shutil.rmtree(workdir, ignore_errors=True)

print("SUCCESS")
PY_EOF

if /home/user/venv/bin/python /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
