#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'SITE_EOF' > /tmp/sitecustomize.py
import atexit
import builtins
import importlib
import io
import json
import os
import subprocess
import sys
import time

_evidence = {
    "compute_calls": 0,
    "fast_math_imported": False,
    "main_imported": False,
    "timer_calls": 0,
    "memory_observations": 0,
}
_last_data = None
_expected_sum = 4999950000.0


def _wrap_fast_math(module):
    global _last_data
    if module is None or getattr(module, "__bench_wrapped__", False):
        return module
    original = getattr(module, "compute_sum", None)
    if original is None:
        return module

    def checked_compute_sum(data, *args, **kwargs):
        global _last_data
        valid = data is _last_data
        if not valid:
            valid = (
                isinstance(data, list)
                and len(data) == 100000
                and data[0] == 0.0
                and data[1] == 1.0
                and data[12345] == 12345.0
                and data[50000] == 50000.0
                and data[-1] == 99999.0
                and sum(data) == _expected_sum
                and all(value == float(index) for index, value in enumerate(data))
            )
            if valid:
                _last_data = data
        if valid:
            _evidence["compute_calls"] += 1
        return original(data, *args, **kwargs)

    module.compute_sum = checked_compute_sum
    module.__bench_wrapped__ = True
    return module


_original_import = builtins.__import__
def _tracked_import(name, globals=None, locals=None, fromlist=(), level=0):
    module = _original_import(name, globals, locals, fromlist, level)
    if name == "fast_math" or name.startswith("fast_math."):
        _evidence["fast_math_imported"] = True
        _wrap_fast_math(sys.modules.get("fast_math"))
    if name == "main" or name.startswith("main."):
        _evidence["main_imported"] = True
    return module
builtins.__import__ = _tracked_import

_original_import_module = importlib.import_module
def _tracked_import_module(name, package=None):
    module = _original_import_module(name, package)
    if name == "fast_math":
        _evidence["fast_math_imported"] = True
        _wrap_fast_math(module)
    if name == "main":
        _evidence["main_imported"] = True
    return module
importlib.import_module = _tracked_import_module

for _timer_name in ("perf_counter", "monotonic", "process_time", "time"):
    _original_timer = getattr(time, _timer_name)
    def _make_timer(fn):
        def _timer(*args, **kwargs):
            _evidence["timer_calls"] += 1
            return fn(*args, **kwargs)
        return _timer
    setattr(time, _timer_name, _make_timer(_original_timer))

try:
    import resource
    _original_getrusage = resource.getrusage
    def _getrusage(*args, **kwargs):
        _evidence["memory_observations"] += 1
        return _original_getrusage(*args, **kwargs)
    resource.getrusage = _getrusage
except Exception:
    pass

try:
    import tracemalloc
    for _name in ("get_traced_memory", "get_tracemalloc_memory"):
        if hasattr(tracemalloc, _name):
            _fn = getattr(tracemalloc, _name)
            def _make_trace(fn):
                def _trace(*args, **kwargs):
                    _evidence["memory_observations"] += 1
                    return fn(*args, **kwargs)
                return _trace
            setattr(tracemalloc, _name, _make_trace(_fn))
except Exception:
    pass

_original_open = builtins.open
def _tracked_open(file, *args, **kwargs):
    try:
        if os.fspath(file).startswith("/proc/"):
            _evidence["memory_observations"] += 1
    except Exception:
        pass
    return _original_open(file, *args, **kwargs)
builtins.open = _tracked_open

_original_io_open = io.open
def _tracked_io_open(file, *args, **kwargs):
    try:
        if os.fspath(file).startswith("/proc/"):
            _evidence["memory_observations"] += 1
    except Exception:
        pass
    return _original_io_open(file, *args, **kwargs)
io.open = _tracked_io_open

_original_popen = subprocess.Popen
def _tracked_popen(*args, **kwargs):
    command = kwargs.get("args", args[0] if args else "")
    text = " ".join(map(str, command)) if isinstance(command, (list, tuple)) else str(command)
    if "ps " in text or text.strip().startswith("ps") or "/proc/" in text:
        _evidence["memory_observations"] += 1
    return _original_popen(*args, **kwargs)
subprocess.Popen = _tracked_popen


def _write_evidence():
    _evidence["fast_math_imported"] = _evidence["fast_math_imported"] or "fast_math" in sys.modules
    _evidence["main_imported"] = _evidence["main_imported"] or "main" in sys.modules
    try:
        with _original_open("/tmp/bench_evidence.json", "w") as handle:
            json.dump(_evidence, handle)
    except Exception:
        pass
atexit.register(_write_evidence)
SITE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import shutil
import subprocess
import sysconfig
import time
import pytest

APP = "/home/user/legacy_app"


def test_fast_math_c_fixed():
    filepath = "/home/user/legacy_app/fast_math.c"
    assert os.path.isfile(filepath), f"{filepath} is missing."

    with open(filepath, "r") as f:
        content = f.read()

    assert "free" in content, "Memory leak not fixed: 'free' not found in fast_math.c"
    assert "i <= num_lines" not in content, "Undefined behavior not fixed: 'i <= num_lines' still present in fast_math.c"


def test_main_py_python3_compatible():
    filepath = "/home/user/legacy_app/main.py"
    assert os.path.isfile(filepath), f"{filepath} is missing."

    with open(filepath, "r") as f:
        content = f.read()

    assert 'print "' not in content and "print '" not in content, "main.py still contains Python 2 print syntax (without parentheses)."
    assert "xrange" not in content, "main.py still contains 'xrange', which is removed in Python 3."
    assert "except Exception," not in content, "main.py still contains Python 2 exception syntax ('except Exception, e:')."


def test_test_and_bench_runs_and_generates_json():
    script_path = "/home/user/legacy_app/test_and_bench.py"
    assert os.path.isfile(script_path), f"{script_path} is missing."

    for artifact in glob.glob(os.path.join(APP, "fast_math*.so")) + glob.glob(os.path.join(APP, "fast_math*.pyd")):
        os.remove(artifact)
    shutil.rmtree(os.path.join(APP, "build"), ignore_errors=True)
    for path in (os.path.join(APP, "migration_results.json"), "/tmp/bench_evidence.json"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp" + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    started = time.monotonic()
    result = subprocess.run(
        ["python3", "test_and_bench.py"],
        cwd=APP,
        capture_output=True,
        text=True,
        env=env,
        timeout=240,
    )
    elapsed = time.monotonic() - started
    assert result.returncode == 0, f"test_and_bench.py execution failed. Stderr:\n{result.stderr}"

    extension_files = glob.glob(os.path.join(APP, "fast_math*.so")) + glob.glob(os.path.join(APP, "fast_math*.pyd"))
    assert extension_files, "test_and_bench.py did not build an in-place fast_math extension."

    evidence_path = "/tmp/bench_evidence.json"
    assert os.path.isfile(evidence_path), "Benchmark execution evidence was not produced."
    with open(evidence_path) as f:
        evidence = json.load(f)
    assert evidence.get("fast_math_imported") is True, "test_and_bench.py did not import fast_math."
    assert evidence.get("main_imported") is True, "test_and_bench.py did not import main."
    assert evidence.get("compute_calls", 0) >= 1100, "Expected 100 benchmark iterations and 1,000 memory-test iterations on the required data."
    assert evidence.get("timer_calls", 0) >= 2, "The benchmark did not measure elapsed time."
    assert evidence.get("memory_observations", 0) >= 2, "The script did not observe memory before and after its memory test."

    json_path = "/home/user/legacy_app/migration_results.json"
    assert os.path.isfile(json_path), f"{json_path} was not generated by test_and_bench.py."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("migration_results.json does not contain valid JSON.")

    expected_keys = {
        "build_success",
        "python3_compatible",
        "average_execution_time_seconds",
        "memory_leak_fixed",
        "sum_result",
    }
    assert set(data) == expected_keys, "migration_results.json does not strictly match the required schema."
    assert data.get("build_success") is True, "JSON key 'build_success' must be true."
    assert data.get("python3_compatible") is True, "JSON key 'python3_compatible' must be true."
    assert data.get("memory_leak_fixed") is True, "JSON key 'memory_leak_fixed' must be true."

    assert isinstance(data["average_execution_time_seconds"], float), "'average_execution_time_seconds' must be a float."
    assert math.isfinite(data["average_execution_time_seconds"]), "Average execution time must be finite."
    assert 0.0 < data["average_execution_time_seconds"] <= elapsed, "Average execution time is not a plausible measured duration."

    expected_sum = sum(float(i) for i in range(100000))
    actual_sum = data.get("sum_result")
    assert actual_sum is not None, "JSON missing 'sum_result'."
    assert isinstance(actual_sum, float), "'sum_result' must be a float."
    assert abs(actual_sum - expected_sum) < 1.0, f"Expected sum around {expected_sum}, but got {actual_sum}."


def test_built_extension_and_main_behave_correctly():
    code = r'''
import gc
import json
import os
import random
import fast_math
import main

cases = [[], [1.0], [1.5, -2.0, 4.25], [float(i) for i in range(257)]]
rng = random.Random(93471)
for _ in range(20):
    values = [rng.uniform(-10000.0, 10000.0) for _ in range(rng.randrange(0, 500))]
    cases.append(values)
for values in cases:
    actual = fast_math.compute_sum(values)
    expected = sum(values)
    assert isinstance(actual, float)
    assert abs(actual - expected) <= 1e-9 * max(1.0, abs(expected))
assert abs(main.run_pipeline([1.0, 2.0, 3.0]) - 6.0) < 1e-12

data = [float(i) for i in range(100000)]
for _ in range(100):
    assert fast_math.compute_sum(data) == 4999950000.0
gc.collect()
def rss_kb():
    with open('/proc/self/status') as handle:
        for line in handle:
            if line.startswith('VmRSS:'):
                return int(line.split()[1])
    raise AssertionError('VmRSS unavailable')
before = rss_kb()
for _ in range(1000):
    assert fast_math.compute_sum(data) == 4999950000.0
gc.collect()
after = rss_kb()
print(json.dumps({'growth_kb': after - before}))
'''
    env = os.environ.copy()
    env["PYTHONPATH"] = APP
    result = subprocess.run(["python3", "-c", code], cwd=APP, env=env, capture_output=True, text=True, timeout=180)
    assert result.returncode == 0, f"Built extension failed behavioral or memory tests:\n{result.stderr}"
    measurement = json.loads(result.stdout.strip().splitlines()[-1])
    assert measurement["growth_kb"] < 32768, f"fast_math leaked excessive memory: RSS grew by {measurement['growth_kb']} KiB."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
