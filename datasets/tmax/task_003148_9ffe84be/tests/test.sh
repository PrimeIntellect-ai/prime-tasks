#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import re
import stat
import subprocess

import pytest

SEARCH_PATH = "/home/user/search.py"
RUN_PATH = "/home/user/run_experiment.sh"
METRICS_PATH = "/home/user/metrics.json"


def test_run_experiment_exists_and_executable():
    assert os.path.isfile(RUN_PATH), f"{RUN_PATH} does not exist."
    st = os.stat(RUN_PATH)
    assert st.st_mode & stat.S_IXUSR, f"{RUN_PATH} is not executable."


def test_search_py_exists():
    assert os.path.isfile(SEARCH_PATH), f"{SEARCH_PATH} does not exist."


def _max_loop_depth(node, depth=0):
    best = depth
    for child in ast.iter_child_nodes(node):
        if isinstance(child, (ast.For, ast.AsyncFor, ast.While)):
            best = max(best, _max_loop_depth(child, depth + 1))
        else:
            best = max(best, _max_loop_depth(child, depth))
    return best


def test_search_implementation_structure():
    with open(SEARCH_PATH, "r") as f:
        source = f.read()
    tree = ast.parse(source, filename=SEARCH_PATH)

    forbidden = {"torch", "tensorflow"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            assert not any(alias.name.split(".")[0] in forbidden for alias in node.names), "ML frameworks are not allowed."
        elif isinstance(node, ast.ImportFrom) and node.module:
            assert node.module.split(".")[0] not in forbidden, "ML frameworks are not allowed."

    functions = {node.name: node for node in ast.walk(tree) if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))}
    assert "naive_search" in functions, "search.py must define naive_search."
    assert "optimized_search" in functions, "search.py must define optimized_search."

    naive = functions["naive_search"]
    optimized = functions["optimized_search"]
    assert _max_loop_depth(naive) >= 2, "naive_search must use nested Python loops over queries and documents."

    loop_nodes = (ast.For, ast.AsyncFor, ast.While, ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp)
    assert not any(isinstance(node, loop_nodes) for node in ast.walk(optimized)), \
        "optimized_search must not loop over queries or documents."


def test_run_experiment_executes_search_and_succeeds():
    with open(RUN_PATH, "r") as f:
        shell_source = f.read()

    assert re.search(r"python(?:3)?[^\n]*search\.py", shell_source), \
        "run_experiment.sh must run search.py with Python."
    install_lines = [line.lower() for line in shell_source.splitlines() if "install" in line.lower() and "pip" in line.lower()]
    assert any("numpy" in line and "h5py" in line for line in install_lines), \
        "run_experiment.sh must install the required NumPy and h5py dependencies."

    if os.path.exists(METRICS_PATH):
        os.remove(METRICS_PATH)
    result = subprocess.run([RUN_PATH], cwd="/home/user", capture_output=True, text=True, timeout=600)
    assert result.returncode == 0, f"run_experiment.sh failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert "Experiment completed successfully" in result.stdout, "Required success message was not printed to stdout."
    assert os.path.isfile(METRICS_PATH), "run_experiment.sh did not create metrics.json."


def test_actual_search_functions_and_reported_error():
    # Execute search.py itself and capture the matrices returned by both required
    # functions. This verifies that the artifact really calls and exercises them.
    validation = r'''
import json
import math
import runpy
import sys

import h5py
import numpy as np

captured = {}
def profiler(frame, event, arg):
    if event == "return" and frame.f_code.co_name in ("naive_search", "optimized_search"):
        captured[frame.f_code.co_name] = arg
    return profiler

sys.setprofile(profiler)
try:
    runpy.run_path("/home/user/search.py", run_name="__main__")
finally:
    sys.setprofile(None)

assert "naive_search" in captured, "search.py did not execute naive_search"
assert "optimized_search" in captured, "search.py did not execute optimized_search"
naive = np.asarray(captured["naive_search"])
optimized = np.asarray(captured["optimized_search"])
assert naive.shape == (100, 10000), f"naive_search returned shape {naive.shape}"
assert optimized.shape == (100, 10000), f"optimized_search returned shape {optimized.shape}"
assert np.isfinite(naive).all(), "naive_search returned non-finite values"
assert np.isfinite(optimized).all(), "optimized_search returned non-finite values"

docs = []
for i in range(5):
    with h5py.File(f"/home/user/data/docs_{i}.h5", "r") as f:
        docs.append(f["embeddings"][:])
docs = np.vstack(docs)
with h5py.File("/home/user/queries.h5", "r") as f:
    queries = f["queries"][:]
expected = (queries / np.linalg.norm(queries, axis=1, keepdims=True)) @ (docs / np.linalg.norm(docs, axis=1, keepdims=True)).T
assert np.allclose(naive, expected, rtol=2e-5, atol=2e-5), "naive_search produced incorrect similarities"
assert np.allclose(optimized, expected, rtol=2e-5, atol=2e-5), "optimized_search produced incorrect similarities"
actual_error = float(np.max(np.abs(naive - optimized)))

with open("/home/user/metrics.json", "r") as f:
    metrics = json.load(f)
reported = metrics["max_abs_error"]
assert isinstance(reported, (int, float)) and not isinstance(reported, bool)
assert math.isfinite(float(reported))
assert math.isclose(float(reported), actual_error, rel_tol=1e-5, abs_tol=1e-12), \
    f"reported max_abs_error {reported} does not match measured error {actual_error}"
'''
    result = subprocess.run(["python3", "-c", validation], capture_output=True, text=True, timeout=600)
    assert result.returncode == 0, f"search.py behavioral validation failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"


def test_metrics_json_validity_and_contents():
    assert os.path.isfile(METRICS_PATH), f"{METRICS_PATH} does not exist. Did run_experiment.sh run successfully?"

    with open(METRICS_PATH, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{METRICS_PATH} is not a valid JSON file.")

    required_keys = ["max_abs_error", "naive_time_sec", "optimized_time_sec", "speedup", "top_5_indices"]
    for key in required_keys:
        assert key in metrics, f"Key '{key}' is missing from metrics.json."
    assert set(metrics) == set(required_keys), "metrics.json must contain exactly the required keys."

    assert isinstance(metrics["max_abs_error"], (int, float)) and not isinstance(metrics["max_abs_error"], bool), "max_abs_error must be a float."
    assert math.isfinite(float(metrics["max_abs_error"])), "max_abs_error must be finite."
    assert metrics["max_abs_error"] < 1e-4, f"max_abs_error {metrics['max_abs_error']} is not < 1e-4."

    for key in ("naive_time_sec", "optimized_time_sec", "speedup"):
        assert isinstance(metrics[key], (int, float)) and not isinstance(metrics[key], bool), f"{key} must be a float."
        assert math.isfinite(float(metrics[key])), f"{key} must be finite."
    assert metrics["naive_time_sec"] > 0, "naive_time_sec must be positive."
    assert metrics["optimized_time_sec"] > 0, "optimized_time_sec must be positive."
    measured_ratio = metrics["naive_time_sec"] / metrics["optimized_time_sec"]
    assert math.isclose(metrics["speedup"], measured_ratio, rel_tol=1e-6, abs_tol=1e-9), \
        "speedup must equal naive_time_sec / optimized_time_sec."
    assert metrics["speedup"] > 1.0, f"speedup {metrics['speedup']} is not > 1.0. Optimized search should be faster."

    assert isinstance(metrics["top_5_indices"], list), "top_5_indices must be a list."
    assert len(metrics["top_5_indices"]) == 100, f"Expected 100 queries in top_5_indices, got {len(metrics['top_5_indices'])}."

    verify_script = r'''
import h5py
import numpy as np
import json

docs = []
for i in range(5):
    with h5py.File(f"/home/user/data/docs_{i}.h5", "r") as f:
        docs.append(f["embeddings"][:])
docs = np.vstack(docs)
with h5py.File("/home/user/queries.h5", "r") as f:
    queries = f["queries"][:]
docs_norm = docs / np.linalg.norm(docs, axis=1, keepdims=True)
queries_norm = queries / np.linalg.norm(queries, axis=1, keepdims=True)
sim = queries_norm @ docs_norm.T
print(json.dumps(np.argsort(-sim, axis=1)[:, :5].tolist()))
'''
    result = subprocess.run(["python3", "-c", verify_script], capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, f"Failed to compute expected indices: {result.stderr}"
    expected_top_5 = json.loads(result.stdout)
    assert metrics["top_5_indices"] == expected_top_5, "top_5_indices do not match the expected canonical values."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
