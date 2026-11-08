#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.machinery
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
import pytest

RESULTS_PATH = "/home/user/benchmark_results.json"
BENCHMARK_PATH = "/home/user/benchmark.py"
SETUP_PATH = "/app/fastvec-1.0/setup.py"
THRESHOLD = 0.25


def test_benchmark_results_exist():
    assert os.path.exists(BENCHMARK_PATH), f"Required benchmark script {BENCHMARK_PATH} does not exist."
    assert os.path.isfile(BENCHMARK_PATH), f"{BENCHMARK_PATH} is not a file."
    assert os.path.exists(SETUP_PATH), f"Vendored build file {SETUP_PATH} does not exist."
    assert os.path.isfile(SETUP_PATH), f"{SETUP_PATH} is not a file."


def test_build_configuration_and_installation():
    with open(SETUP_PATH, "r") as f:
        setup_source = f.read()

    try:
        tree = ast.parse(setup_source, filename=SETUP_PATH)
    except SyntaxError as exc:
        pytest.fail(f"setup.py is not valid Python: {exc}")

    string_constants = [
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    ]
    assert not any("-O0" in value.split() for value in string_constants), (
        "setup.py still configures the fastvec extension with the optimization-disabling -O0 flag."
    )

    try:
        import fastvec
    except Exception as exc:
        pytest.fail(f"Failed to import the installed fastvec package: {exc}")

    module_path = os.path.realpath(getattr(fastvec, "__file__", ""))
    assert module_path and os.path.isfile(module_path), "fastvec does not resolve to an installed module file."
    assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), (
        f"fastvec must be the compiled C extension, but it resolved to {module_path!r}."
    )
    assert hasattr(fastvec, "Index"), "The installed fastvec extension has no Index type."


def run_instrumented_benchmark():
    helper_source = r'''
import json
import os
import runpy
import sys
import time
import types
import numpy as np

measurement_path = sys.argv[1]
benchmark_path = sys.argv[2]

# Import the installed extension before exposing the proxy to benchmark.py.
import fastvec as real_fastvec
_clock = time.perf_counter
calls = []

class InstrumentedIndex:
    def __init__(self, refs, *args, **kwargs):
        self._refs_shape = list(np.shape(refs))
        self._inner = real_fastvec.Index(refs, *args, **kwargs)

    def query(self, queries, k=5):
        start = _clock()
        result = self._inner.query(queries, k=k)
        elapsed = _clock() - start
        calls.append({
            "refs_shape": self._refs_shape,
            "queries_shape": list(np.shape(queries)),
            "k": int(k),
            "elapsed": elapsed,
            "indices": np.asarray(result).tolist(),
        })
        return result

proxy = types.ModuleType("fastvec")
proxy.Index = InstrumentedIndex
proxy.__file__ = getattr(real_fastvec, "__file__", None)
def _proxy_getattr(name):
    return getattr(real_fastvec, name)
proxy.__getattr__ = _proxy_getattr
sys.modules["fastvec"] = proxy

runpy.run_path(benchmark_path, run_name="__main__")

with open(measurement_path, "w") as f:
    json.dump({"calls": calls}, f)
'''

    helper_path = "/tmp/run_benchmark_instrumented.py"
    with open(helper_path, "w") as f:
        f.write(helper_source)

    fd, measurement_path = tempfile.mkstemp(prefix="fastvec_measurement_", suffix=".json")
    os.close(fd)
    os.unlink(measurement_path)

    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    try:
        completed = subprocess.run(
            [sys.executable, helper_path, measurement_path, BENCHMARK_PATH],
            cwd="/tmp",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=300,
        )
        assert completed.returncode == 0, (
            f"Executing {BENCHMARK_PATH} failed with exit code {completed.returncode}:\n"
            f"{completed.stdout}"
        )
        assert os.path.isfile(measurement_path), "The instrumented benchmark did not complete normally."
        with open(measurement_path, "r") as f:
            return json.load(f)
    finally:
        if os.path.exists(measurement_path):
            os.unlink(measurement_path)


def test_benchmark_performance_and_correctness():
    measurements = run_instrumented_benchmark()

    assert os.path.exists(RESULTS_PATH), (
        f"Output file {RESULTS_PATH} does not exist. Did you run the benchmark script?"
    )
    assert os.path.isfile(RESULTS_PATH), f"{RESULTS_PATH} is not a file."

    with open(RESULTS_PATH, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Failed to parse JSON from {RESULTS_PATH}")

    assert "inference_time_seconds" in results, "Missing 'inference_time_seconds' in results JSON"
    assert "top_5_indices" in results, "Missing 'top_5_indices' in results JSON"

    time_taken = results["inference_time_seconds"]
    assert isinstance(time_taken, (int, float)) and not isinstance(time_taken, bool), (
        "inference_time_seconds must be a number"
    )
    assert np.isfinite(time_taken) and time_taken >= 0, (
        "inference_time_seconds must be a finite, non-negative measured duration"
    )
    assert time_taken < THRESHOLD, (
        f"Inference too slow: {time_taken}s (threshold {THRESHOLD}s). "
        "Did you fix the C-extension optimization flags in setup.py and reinstall the package?"
    )

    matching_calls = [
        call for call in measurements.get("calls", [])
        if call.get("refs_shape") == [100000, 128]
        and call.get("queries_shape") == [1000, 128]
        and call.get("k") == 5
    ]
    assert matching_calls, (
        "benchmark.py did not call fastvec.Index.query on the complete projected reference and query arrays with k=5."
    )
    measured_call = matching_calls[-1]
    measured_time = measured_call["elapsed"]
    assert measured_time < THRESHOLD, (
        f"Verifier-measured fastvec inference took {measured_time}s "
        f"(threshold {THRESHOLD}s)."
    )

    tolerance = max(0.02, measured_time * 0.25)
    assert abs(time_taken - measured_time) <= tolerance, (
        f"Reported inference time {time_taken}s does not match the verifier-observed "
        f"query duration {measured_time}s."
    )

    agent_indices = results["top_5_indices"]
    assert np.array_equal(agent_indices, measured_call["indices"]), (
        "top_5_indices were not the results returned by the required fastvec query."
    )

    try:
        refs = np.vstack([np.load(f"/home/user/data/ref_chunk_{i}.npy") for i in range(10)])
        queries = np.load("/home/user/data/queries.npy")
        pca = np.load("/home/user/data/pca_matrix.npy")
    except Exception as exc:
        pytest.fail(f"Failed to load data files for verification: {exc}")

    proj_refs = refs @ pca.T
    proj_queries = queries @ pca.T

    dists = (
        np.sum(proj_queries**2, axis=1, keepdims=True)
        + np.sum(proj_refs**2, axis=1)
        - 2 * np.dot(proj_queries, proj_refs.T)
    )
    expected_indices = np.argsort(dists, axis=1)[:, :5].tolist()

    assert len(agent_indices) == len(expected_indices), (
        f"Expected {len(expected_indices)} query results, got {len(agent_indices)}"
    )
    assert np.array_equal(agent_indices, expected_indices), (
        "Top 5 indices do not match the ground truth PCA projection and KNN logic."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
