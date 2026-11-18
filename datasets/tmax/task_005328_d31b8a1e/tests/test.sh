#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.machinery
import importlib.util
import json
import math
import os
import random
import subprocess
import sys
import tempfile

import pytest

PROJECT_DIR = "/home/user/project"


def run(cmd, **kwargs):
    return subprocess.run(cmd, cwd=PROJECT_DIR, capture_output=True, text=True, timeout=180, **kwargs)


def test_rust_source_compiles():
    result = run(["cargo", "check", "--quiet"])
    assert result.returncode == 0, f"Rust project does not compile.\nStdout: {result.stdout}\nStderr: {result.stderr}"


def load_extension():
    sys.path.insert(0, PROJECT_DIR)
    spec = importlib.util.find_spec("data_processor")
    assert spec is not None, "Failed to find 'data_processor'. Ensure the extension was built successfully."
    assert isinstance(spec.loader, importlib.machinery.ExtensionFileLoader), \
        f"data_processor must be a compiled Python extension, not {spec.origin!r}"
    assert spec.origin and any(spec.origin.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES)
    import data_processor
    return data_processor


def test_module_import_and_functionality():
    data_processor = load_extension()
    assert hasattr(data_processor, "process_data"), "Module 'data_processor' lacks 'process_data' function."

    fixed = [3, 1, 2, 3, 4, 1, 5]
    assert data_processor.process_data(fixed) == sorted(list(set(fixed)))

    rng = random.SystemRandom()
    cases = [
        [], [0], [1, 1, 1], [5, -1, 5, 0, -1],
        [-2147483648, 2147483647, 0, -2147483648],
        list(range(50, -51, -1)),
    ]
    for _ in range(20):
        cases.append([rng.randint(-2_000_000_000, 2_000_000_000) for _ in range(rng.randint(0, 400))])
    for values in cases:
        original = list(values)
        actual = data_processor.process_data(values)
        assert actual == sorted(list(set(original))), f"Incorrect result for input {original[:20]!r}"
        assert values == original, "process_data modified its input list"


def test_prop_script():
    script_path = os.path.join(PROJECT_DIR, "test_prop.py")
    assert os.path.isfile(script_path), f"Script not found: {script_path}"
    content = open(script_path, encoding="utf-8").read()
    assert "hypothesis" in content, "test_prop.py does not seem to use the 'hypothesis' library."

    tree = ast.parse(content, script_path)
    names = {n.id for n in ast.walk(tree) if isinstance(n, ast.Name)}
    attrs = {n.attr for n in ast.walk(tree) if isinstance(n, ast.Attribute)}
    imported_hypothesis = any(
        isinstance(n, (ast.Import, ast.ImportFrom)) and
        ((isinstance(n, ast.Import) and any(a.name == "hypothesis" for a in n.names)) or
         (isinstance(n, ast.ImportFrom) and n.module and n.module.startswith("hypothesis")))
        for n in ast.walk(tree)
    )
    assert imported_hypothesis
    assert "given" in names | attrs, "test_prop.py must define a Hypothesis @given test"
    assert "lists" in names | attrs and "integers" in names | attrs, "Hypothesis must generate lists of integers"
    assert "sorted" in names and "set" in names, "The property must compare against Python sorted/set behavior"
    assert any(isinstance(n, ast.Assert) for n in ast.walk(tree)), "The property test must contain an assertion"

    result = run([sys.executable, script_path])
    assert result.returncode == 0, f"test_prop.py failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    meta = instrument_script(script_path, "prop")
    assert meta["calls"] >= 10, "Running test_prop.py did not exercise process_data as a property test"
    assert meta["distinct"] >= 5, "The property test did not exercise sufficiently varied generated inputs"
    assert meta["all_integer_lists"], "The property test must call process_data with lists of integers"


HARNESS = r'''
import importlib, json, os, runpy, sys, time, types
project, script, mode, meta_path = sys.argv[1:5]
sys.path.insert(0, project)
real = importlib.import_module("data_processor")
proxy = types.ModuleType("data_processor")
state = {"calls": 0, "distinct_values": set(), "all_integer_lists": True,
         "benchmark_ok": True, "same_benchmark_input": True, "first_fp": None,
         "memory_len_ok": False, "memory_tracing": False}
delay = float(os.environ.get("VERIFY_DELAY", "0"))
secret_peak = int(os.environ.get("VERIFY_PEAK", "0"))

def process_data(value):
    state["calls"] += 1
    is_list = isinstance(value, list)
    ints = is_list and all(isinstance(x, int) and not isinstance(x, bool) for x in value)
    state["all_integer_lists"] = state["all_integer_lists"] and ints
    if mode == "prop":
        try: state["distinct_values"].add(tuple(value))
        except Exception: state["all_integer_lists"] = False
    elif mode == "bench":
        ok = ints and len(value) == 100000 and all(0 <= x <= 100000 for x in value)
        state["benchmark_ok"] = state["benchmark_ok"] and ok
        fp = hash(tuple(value)) if is_list else None
        if state["first_fp"] is None: state["first_fp"] = fp
        else: state["same_benchmark_input"] = state["same_benchmark_input"] and fp == state["first_fp"]
        time.sleep(delay)
    elif mode == "memory":
        import tracemalloc
        state["memory_len_ok"] = ints and len(value) == 500000
        state["memory_tracing"] = tracemalloc.is_tracing()
    return real.process_data(value)

proxy.process_data = process_data
sys.modules["data_processor"] = proxy

if mode == "memory":
    real_tm = importlib.import_module("tracemalloc")
    fake_tm = types.ModuleType("tracemalloc")
    started = {"value": False}
    class Stat:
        def __init__(self, size): self.size = size
    class Snapshot:
        def statistics(self, *args, **kwargs): return [Stat(secret_peak)]
    def start(*args, **kwargs):
        started["value"] = True
        return real_tm.start(*args, **kwargs)
    def get_traced_memory():
        current, _ = real_tm.get_traced_memory()
        return current, secret_peak
    def take_snapshot():
        return Snapshot()
    for name in dir(real_tm):
        setattr(fake_tm, name, getattr(real_tm, name))
    fake_tm.start = start
    fake_tm.get_traced_memory = get_traced_memory
    fake_tm.take_snapshot = take_snapshot
    sys.modules["tracemalloc"] = fake_tm

exit_code = 0
try:
    runpy.run_path(script, run_name="__main__")
except SystemExit as e:
    exit_code = e.code if isinstance(e.code, int) else (0 if e.code is None else 1)
finally:
    output = {
        "calls": state["calls"],
        "distinct": len(state["distinct_values"]),
        "all_integer_lists": state["all_integer_lists"],
        "benchmark_ok": state["benchmark_ok"],
        "same_benchmark_input": state["same_benchmark_input"],
        "memory_len_ok": state["memory_len_ok"],
        "memory_tracing": state["memory_tracing"],
        "tracemalloc_started": started["value"] if mode == "memory" else False,
        "exit_code": exit_code,
    }
    with open(meta_path, "w") as f: json.dump(output, f)
if exit_code:
    raise SystemExit(exit_code)
'''


def instrument_script(script, mode, delay=0.0, peak=0):
    fd, meta_path = tempfile.mkstemp(prefix="verify-meta-", suffix=".json")
    os.close(fd)
    os.unlink(meta_path)
    env = os.environ.copy()
    env["VERIFY_DELAY"] = str(delay)
    env["VERIFY_PEAK"] = str(peak)
    result = subprocess.run(
        [sys.executable, "-c", HARNESS, PROJECT_DIR, script, mode, meta_path],
        cwd=PROJECT_DIR, env=env, capture_output=True, text=True, timeout=180)
    assert result.returncode == 0, f"{os.path.basename(script)} failed.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert os.path.isfile(meta_path), "Instrumentation metadata was not produced"
    with open(meta_path) as f:
        meta = json.load(f)
    os.unlink(meta_path)
    return meta


def read_benchmark():
    path = os.path.join(PROJECT_DIR, "benchmark.json")
    assert os.path.isfile(path), f"Benchmark result not found: {path}"
    try:
        with open(path) as f: data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("benchmark.json is not valid JSON.")
    assert set(data) == {"avg_time_sec"}, "benchmark.json must contain only avg_time_sec"
    value = data["avg_time_sec"]
    assert isinstance(value, (int, float)) and not isinstance(value, bool), "'avg_time_sec' must be a number."
    assert math.isfinite(value) and value >= 0
    return float(value)


def test_benchmark_script_and_json():
    script = os.path.join(PROJECT_DIR, "benchmark.py")
    assert os.path.isfile(script), f"Script not found: {script}"
    output = os.path.join(PROJECT_DIR, "benchmark.json")

    if os.path.exists(output): os.unlink(output)
    first = instrument_script(script, "bench", delay=0.005)
    value1 = read_benchmark()
    assert first["calls"] == 50, "benchmark.py must call process_data exactly 50 times"
    assert first["benchmark_ok"] and first["same_benchmark_input"], \
        "benchmark.py must reuse one random list of 100,000 integers in the required range"

    os.unlink(output)
    second = instrument_script(script, "bench", delay=0.055)
    value2 = read_benchmark()
    assert second["calls"] == 50
    assert second["benchmark_ok"] and second["same_benchmark_input"]
    assert 0.035 <= value2 - value1 <= 0.080, \
        "avg_time_sec does not reflect the measured average of the 50 process_data calls"


def test_memory_script_and_txt():
    script = os.path.join(PROJECT_DIR, "profile_mem.py")
    assert os.path.isfile(script), f"Script not found: {script}"
    output = os.path.join(PROJECT_DIR, "memory.txt")
    if os.path.exists(output): os.unlink(output)
    secret_peak = random.SystemRandom().randint(20_000_000, 90_000_000)
    meta = instrument_script(script, "memory", peak=secret_peak)
    assert meta["calls"] >= 1 and meta["memory_len_ok"], \
        "profile_mem.py must process a random list of 500,000 integers"
    assert meta["tracemalloc_started"] and meta["memory_tracing"], \
        "tracemalloc must be started before process_data is called"

    assert os.path.isfile(output), f"Memory result not found: {output}"
    content = open(output).read().strip()
    try:
        mem_usage = int(content)
    except ValueError:
        pytest.fail(f"memory.txt does not contain a valid integer. Found: {content}")
    assert mem_usage >= 0, "Memory usage should be a non-negative integer."
    assert mem_usage == secret_peak, "memory.txt does not contain the peak reported by tracemalloc"
    assert content == str(mem_usage), "memory.txt must contain only the integer peak byte count"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
