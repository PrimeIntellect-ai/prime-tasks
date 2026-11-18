#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib
import json
import math
import os
import subprocess
import sys
import time

import pytest

HOME = "/home/user"


def run_script(path, timeout=120):
    env = os.environ.copy()
    env["PYTHONPATH"] = HOME + os.pathsep + env.get("PYTHONPATH", "")
    return subprocess.run(
        [sys.executable, path], cwd=HOME, env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=timeout
    )


def test_01_required_files_exist():
    required_files = [
        f"{HOME}/spatial_grid.py",
        f"{HOME}/run_queries.py",
        f"{HOME}/benchmark.py",
        f"{HOME}/test_spatial_grid.py",
    ]
    for file_path in required_files:
        assert os.path.exists(file_path), f"Required file {file_path} is missing."
        assert os.path.isfile(file_path), f"Expected {file_path} to be a regular file."
        assert os.path.getsize(file_path) > 0, f"Required file {file_path} is empty."


def load_delivery_grid():
    sys.path.insert(0, HOME)
    try:
        sys.modules.pop("spatial_grid", None)
        module = importlib.import_module("spatial_grid")
    finally:
        if sys.path and sys.path[0] == HOME:
            sys.path.pop(0)
    assert hasattr(module, "DeliveryGrid"), "spatial_grid.py must define DeliveryGrid"
    cls = module.DeliveryGrid
    assert isinstance(cls, type), "DeliveryGrid must be a class"
    return cls


def test_02_delivery_grid_behavior_and_scaling():
    DeliveryGrid = load_delivery_grid()

    grid = DeliveryGrid(10.0)
    assert grid.query_min_cost(0.0, 0.0, 5.0) == -1.0

    grid.insert(3.0, 4.0, 1.0, 2.0)       # distance 5, cost 11
    grid.insert(0.0, 0.0, 20.0, 1.0)
    grid.insert(-1.0, -1.0, 7.125, 0.0)
    assert grid.query_min_cost(0.0, 0.0, 5.0) == 11.0
    assert grid.query_min_cost(3.0, 4.0, 0.0) == 1.0
    assert grid.query_min_cost(-1.0, -1.0, 0.0) == 7.12
    assert grid.query_min_cost(100.0, 100.0, 1.0) == -1.0

    boundary = DeliveryGrid(3.0)
    boundary.insert(-6.0, 8.0, 2.0, 0.333)
    assert boundary.query_min_cost(0.0, 0.0, 10.0) == 5.33
    assert boundary.query_min_cost(0.0, 0.0, 9.999) == -1.0

    # A local query must not degrade linearly with a large number of anchors
    # located in distant cells. This distinguishes a spatial index from a flat scan.
    def make_grid(count):
        g = DeliveryGrid(10.0)
        g.insert(0.0, 0.0, 1.0, 1.0)
        for i in range(count):
            g.insert(10000.0 + (i % 100) * 0.01,
                     10000.0 + (i // 100) * 0.01,
                     10.0, 1.0)
        return g

    small = make_grid(1000)
    large = make_grid(40000)

    def measure(g):
        start = time.perf_counter()
        for _ in range(300):
            assert g.query_min_cost(0.0, 0.0, 1.0) == 1.0
        return time.perf_counter() - start

    small_time = measure(small)
    large_time = measure(large)
    assert large_time <= small_time * 8.0 + 0.05, (
        "query_min_cost appears to scan all anchors rather than querying spatial cells: "
        f"small={small_time:.6f}s large={large_time:.6f}s"
    )


def test_03_user_tests_are_substantive_and_pass():
    test_path = f"{HOME}/test_spatial_grid.py"
    with open(test_path, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=test_path)
    tests = [n for n in ast.walk(tree)
             if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
             and n.name.startswith("test_")]
    assert len(tests) >= 3, "test_spatial_grid.py must define at least 3 test cases"
    assert "DeliveryGrid" in source, "The submitted tests must exercise DeliveryGrid"

    proc = subprocess.run(
        [sys.executable, "-m", "pytest", "-c", "/dev/null", "-q", test_path],
        cwd=HOME, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=120
    )
    assert proc.returncode == 0, "Submitted pytest tests failed:\n" + proc.stdout


def test_04_execute_scripts_and_validate_artifacts():
    benchmark_source = open(f"{HOME}/benchmark.py", encoding="utf-8").read()
    benchmark_tree = ast.parse(benchmark_source, filename=f"{HOME}/benchmark.py")
    assert "DeliveryGrid" in benchmark_source, "benchmark.py must benchmark DeliveryGrid"
    timing_names = {"time", "perf_counter", "monotonic", "process_time", "default_timer"}
    calls = [n for n in ast.walk(benchmark_tree) if isinstance(n, ast.Call)]
    assert any(
        (isinstance(c.func, ast.Name) and c.func.id in timing_names) or
        (isinstance(c.func, ast.Attribute) and c.func.attr in timing_names)
        for c in calls
    ), "benchmark.py must measure elapsed time"
    iterations = [n for n in ast.walk(benchmark_tree)
                  if isinstance(n, (ast.For, ast.ListComp, ast.GeneratorExp))]
    assert iterations, "benchmark.py must iterate over benchmark data"

    results_path = f"{HOME}/query_results.json"
    benchmark_path = f"{HOME}/benchmark_results.json"
    for path in (results_path, benchmark_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    proc = run_script(f"{HOME}/run_queries.py")
    assert proc.returncode == 0, "run_queries.py failed:\n" + proc.stdout + proc.stderr
    assert os.path.isfile(results_path), f"Missing required file: {results_path}"

    benchmark_started = time.time()
    wall_start = time.perf_counter()
    proc = run_script(f"{HOME}/benchmark.py")
    wall_elapsed = time.perf_counter() - wall_start
    assert proc.returncode == 0, "benchmark.py failed:\n" + proc.stdout + proc.stderr
    assert os.path.isfile(benchmark_path), f"Missing required file: {benchmark_path}"
    assert os.path.getmtime(benchmark_path) >= benchmark_started - 1.0, \
        "benchmark_results.json was not freshly produced by benchmark.py"

    with open(benchmark_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{benchmark_path} is not valid JSON")

    assert isinstance(results, dict), f"Expected {benchmark_path} to contain a JSON object"
    expected_keys = {"naive_time_sec", "grid_time_sec", "speedup"}
    assert expected_keys.issubset(results.keys()), \
        f"Missing keys in benchmark_results.json. Expected {expected_keys}"
    for key in expected_keys:
        value = results[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), \
            f"Expected {key} to be a number, got {type(value)}"
        assert math.isfinite(value), f"Expected finite {key}, got {value}"
    naive = results["naive_time_sec"]
    grid_time = results["grid_time_sec"]
    speedup = results["speedup"]
    assert naive > 0 and grid_time > 0 and speedup > 0, "Benchmark timings must be positive"
    assert math.isclose(speedup, naive / grid_time, rel_tol=1e-3, abs_tol=1e-6), \
        "speedup must equal naive_time_sec / grid_time_sec"
    assert naive + grid_time <= wall_elapsed * 1.5 + 0.1, \
        "Reported benchmark durations exceed the script's elapsed runtime"

    with open(f"{HOME}/delivery_zones.json") as f:
        zones = json.load(f)
    with open(f"{HOME}/queries.json") as f:
        queries = json.load(f)

    expected_results = []
    for q in queries:
        qx, qy, radius = q["qx"], q["qy"], q["radius"]
        costs = []
        for z in zones:
            distance = math.hypot(z["x"] - qx, z["y"] - qy)
            if distance <= radius:
                costs.append(z["base_cost"] + z["multiplier"] * distance)
        expected_results.append(round(min(costs), 2) if costs else -1.0)

    with open(results_path) as f:
        try:
            actual_results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{results_path} is not valid JSON")
    assert isinstance(actual_results, list), f"Expected {results_path} to contain a JSON array"
    assert len(actual_results) == len(expected_results), \
        f"Expected {len(expected_results)} results, got {len(actual_results)}"
    for i, (actual, expected) in enumerate(zip(actual_results, expected_results)):
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool), \
            f"Result at index {i} is not numeric"
        assert math.isclose(actual, expected, rel_tol=1e-5, abs_tol=1e-2), \
            f"Result at index {i} is incorrect. Expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -p no:cacheprovider -c /dev/null /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
