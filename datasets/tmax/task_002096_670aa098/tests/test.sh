#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'BENCH_EOF' > /tmp/audit_benchmark.py
import importlib.util
import json
import os
import runpy
import sys
import time
import types

TARGET_DIR = "/home/user/build_cache_optimizer"
CACHE_PATH = os.path.join(TARGET_DIR, "interval_cache.py")
BENCHMARK_PATH = os.path.join(TARGET_DIR, "benchmark.py")
METRICS_PATH = os.path.join(TARGET_DIR, "bench_metrics.json")
AUDIT_PATH = "/tmp/benchmark_audit.json"

spec = importlib.util.spec_from_file_location("real_interval_cache_for_benchmark", CACHE_PATH)
real_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(real_module)

state = {
    "instances": 0,
    "adds": 0,
    "gets": 0,
    "invalid": 0,
    "values": set(),
    "start": None,
    "end": None,
}

class SpyIntervalCache:
    def __init__(self, *args, **kwargs):
        state["instances"] += 1
        if state["start"] is None:
            state["start"] = time.perf_counter()
        self._delegate = real_module.IntervalCache(*args, **kwargs)

    def add_interval(self, start, end):
        state["adds"] += 1
        if not isinstance(start, int) or not isinstance(end, int) or start > end:
            state["invalid"] += 1
        if len(state["values"]) < 1000:
            state["values"].add((start, end))
        return self._delegate.add_interval(start, end)

    def get_merged_intervals(self):
        state["gets"] += 1
        result = self._delegate.get_merged_intervals()
        state["end"] = time.perf_counter()
        return result

fake_module = types.ModuleType("interval_cache")
fake_module.IntervalCache = SpyIntervalCache
sys.modules["interval_cache"] = fake_module

if os.path.exists(METRICS_PATH):
    os.remove(METRICS_PATH)

old_cwd = os.getcwd()
os.chdir(TARGET_DIR)
try:
    runpy.run_path(BENCHMARK_PATH, run_name="__main__")
finally:
    os.chdir(old_cwd)

observed = None
if state["start"] is not None and state["end"] is not None:
    observed = state["end"] - state["start"]

with open(AUDIT_PATH, "w") as f:
    json.dump({
        "instances": state["instances"],
        "adds": state["adds"],
        "gets": state["gets"],
        "invalid": state["invalid"],
        "distinct_sample": len(state["values"]),
        "observed_seconds": observed,
    }, f)
BENCH_EOF

cat << 'MUTANT_EOF' > /tmp/run_property_mutant.py
import os
import sys
import types
import pytest

TARGET = "/home/user/build_cache_optimizer/test_properties.py"
KIND = sys.argv[1]

class IntervalCache:
    def __init__(self):
        self.intervals = []

    def add_interval(self, start, end):
        self.intervals.append((start, end))

    def _correct(self):
        result = []
        for start, end in sorted(self.intervals):
            if not result or result[-1][1] < start:
                result.append((start, end))
            else:
                result[-1] = (result[-1][0], max(result[-1][1], end))
        return result

    def get_merged_intervals(self):
        result = self._correct()
        if KIND == "sorted":
            return list(reversed(result))
        if KIND == "disjoint":
            duplicated = []
            for interval in result:
                duplicated.extend([interval, interval])
            return duplicated
        if KIND == "coverage":
            return result[1:] if result else []
        raise RuntimeError("unknown mutant")

fake = types.ModuleType("interval_cache")
fake.IntervalCache = IntervalCache
sys.modules["interval_cache"] = fake
os.chdir(os.path.dirname(TARGET))
sys.exit(pytest.main(["-q", TARGET]))
MUTANT_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import math
import os
import random
import subprocess
import sys
import time
import pytest

TARGET_DIR = "/home/user/build_cache_optimizer"
INTERVAL_CACHE_PATH = os.path.join(TARGET_DIR, "interval_cache.py")
TEST_PROPERTIES_PATH = os.path.join(TARGET_DIR, "test_properties.py")
BENCHMARK_PATH = os.path.join(TARGET_DIR, "benchmark.py")
METRICS_PATH = os.path.join(TARGET_DIR, "bench_metrics.json")


def load_interval_cache():
    spec = importlib.util.spec_from_file_location("candidate_interval_cache_hidden", INTERVAL_CACHE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.IntervalCache


def reference_merge(intervals):
    merged = []
    for start, end in sorted(intervals):
        if not merged or merged[-1][1] < start:
            merged.append((start, end))
        else:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
    return merged


def test_directory_and_files_exist():
    assert os.path.isdir(TARGET_DIR), f"Directory {TARGET_DIR} does not exist."
    for filepath in [INTERVAL_CACHE_PATH, TEST_PROPERTIES_PATH, BENCHMARK_PATH, METRICS_PATH]:
        assert os.path.isfile(filepath), f"File {filepath} does not exist."


def test_interval_cache_functionality():
    sys.path.insert(0, TARGET_DIR)
    try:
        from interval_cache import IntervalCache
    except ImportError as e:
        pytest.fail(f"Could not import IntervalCache from interval_cache.py: {e}")

    cache = IntervalCache()
    cache.add_interval(1, 5)
    cache.add_interval(2, 6)
    cache.add_interval(8, 10)
    cache.add_interval(10, 15)

    merged = cache.get_merged_intervals()
    assert merged == [(1, 6), (8, 15)], f"Expected [(1, 6), (8, 15)], got {merged}"

    cache2 = IntervalCache()
    cache2.add_interval(10, 12)
    cache2.add_interval(1, 3)
    cache2.add_interval(2, 4)
    cache2.add_interval(5, 7)
    assert cache2.get_merged_intervals() == [(1, 4), (5, 7), (10, 12)]


def test_interval_cache_randomized_against_independent_oracle():
    IntervalCache = load_interval_cache()
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))

    cases = [
        [],
        [(0, 0)],
        [(5, 5), (5, 5)],
        [(-10, -5), (-5, 0), (1, 1)],
        [(100, 200), (-50, 500), (0, 0)],
        [(1, 2), (3, 4), (2, 3)],
    ]
    for _ in range(90):
        intervals = []
        for _ in range(rng.randint(0, 450)):
            start = rng.randint(-10**9, 10**9)
            if rng.random() < 0.25:
                end = start
            else:
                end = start + rng.randint(0, 100000)
            intervals.append((start, end))
        rng.shuffle(intervals)
        cases.append(intervals)

    for intervals in cases:
        cache = IntervalCache()
        for start, end in intervals:
            cache.add_interval(start, end)
        actual = cache.get_merged_intervals()
        expected = reference_merge(intervals)
        assert isinstance(actual, list)
        assert all(isinstance(item, tuple) and len(item) == 2 for item in actual)
        assert actual == expected, f"Incorrect merge for {intervals[:20]}: expected {expected}, got {actual}"
        assert cache.get_merged_intervals() == expected


def test_interval_cache_performance():
    sys.path.insert(0, TARGET_DIR)
    from interval_cache import IntervalCache

    cache = IntervalCache()
    for i in range(200000, 0, -1):
        cache.add_interval(i, i + 2)

    start_time = time.time()
    merged = cache.get_merged_intervals()
    duration = time.time() - start_time

    assert duration < 2.0, f"Performance test failed: took {duration:.2f} seconds, expected < 2.0 seconds."
    assert len(merged) == 1
    assert merged[0] == (1, 200002)


def test_bench_metrics_format():
    with open(METRICS_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("bench_metrics.json is not valid JSON.")

    assert "time_seconds" in data, "Key 'time_seconds' missing from bench_metrics.json."
    assert isinstance(data["time_seconds"], float), "'time_seconds' must be a float."


def test_benchmark_is_executed_and_measures_exact_workload():
    result = subprocess.run(
        [sys.executable, "/tmp/audit_benchmark.py"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"benchmark.py failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(METRICS_PATH), "benchmark.py did not create bench_metrics.json"

    with open("/tmp/benchmark_audit.json") as f:
        audit = json.load(f)
    assert audit["instances"] >= 1, "benchmark did not instantiate IntervalCache"
    assert audit["adds"] == 100000, f"benchmark added {audit['adds']} intervals instead of exactly 100000"
    assert audit["gets"] >= 1, "benchmark did not call get_merged_intervals()"
    assert audit["invalid"] == 0, "benchmark generated invalid intervals"
    assert audit["distinct_sample"] > 100, "benchmark intervals do not appear to be randomly generated"

    with open(METRICS_PATH) as f:
        metrics = json.load(f)
    assert set(metrics) == {"time_seconds"}, "bench_metrics.json must contain exactly the time_seconds field"
    reported = metrics["time_seconds"]
    observed = audit["observed_seconds"]
    assert isinstance(reported, float) and math.isfinite(reported) and reported >= 0
    assert isinstance(observed, float) and observed >= 0
    tolerance = max(0.01, observed * 0.15)
    assert abs(reported - observed) <= tolerance, (
        f"reported benchmark time {reported} does not match observed wall-clock duration {observed}"
    )


def test_property_tests_pass():
    result = subprocess.run(["pytest", TEST_PROPERTIES_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Property tests failed:\n{result.stdout}\n{result.stderr}"


def test_property_tests_are_hypothesis_based_and_nonvacuous():
    source = open(TEST_PROPERTIES_PATH, encoding="utf-8").read()
    tree = ast.parse(source, TEST_PROPERTIES_PATH)
    names = {node.id for node in ast.walk(tree) if isinstance(node, ast.Name)}
    attributes = {node.attr for node in ast.walk(tree) if isinstance(node, ast.Attribute)}
    assert "given" in names or "given" in attributes, "test_properties.py must use Hypothesis @given"
    assert "IntervalCache" in names, "property tests must exercise IntervalCache"
    assert "add_interval" in attributes and "get_merged_intervals" in attributes
    assert any(isinstance(node, ast.Assert) for node in ast.walk(tree)), "property tests contain no assertions"

    for mutant in ["sorted", "disjoint", "coverage"]:
        result = subprocess.run(
            [sys.executable, "/tmp/run_property_mutant.py", mutant],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode != 0, (
            f"Property tests did not detect the {mutant} property violation; tests may be vacuous.\n"
            f"{result.stdout}\n{result.stderr}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
