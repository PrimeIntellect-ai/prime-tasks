#!/bin/bash
set -u
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

rm -f /home/user/output_fast.npy /home/user/report.json

cat > /tmp/run_simulation_checked.py <<'PY'
import builtins
import multiprocessing
import multiprocessing.pool
import os
import runpy
import numpy as np

SIMULATE = "/home/user/simulate.py"
REFERENCE = os.path.realpath("/home/user/reference.npy")

real_open = builtins.open
real_np_load = np.load

def guarded_open(file, mode="r", *args, **kwargs):
    try:
        path = os.path.realpath(os.fspath(file))
    except TypeError:
        path = None
    if path == REFERENCE and "r" in mode:
        raise AssertionError("simulate.py must compute its output, not read reference.npy")
    return real_open(file, mode, *args, **kwargs)

def guarded_load(file, *args, **kwargs):
    try:
        path = os.path.realpath(os.fspath(file))
    except TypeError:
        path = None
    if path == REFERENCE:
        raise AssertionError("simulate.py must compute its output, not load reference.npy")
    return real_np_load(file, *args, **kwargs)

builtins.open = guarded_open
np.load = guarded_load

RealPool = multiprocessing.pool.Pool
pool_sizes = []
submitted_groups = []
submitted_individual = []

def chunk_length(item):
    if isinstance(item, np.ndarray):
        return len(item)
    if isinstance(item, (tuple, list)) and item and isinstance(item[0], np.ndarray):
        return len(item[0])
    return None

class SpyPool:
    def __init__(self, *args, **kwargs):
        processes = kwargs.get("processes", args[0] if args else None)
        pool_sizes.append(processes)
        self._pool = RealPool(*args, **kwargs)

    def _group(self, iterable):
        items = list(iterable)
        submitted_groups.append([chunk_length(item) for item in items])
        return items

    def map(self, func, iterable, chunksize=None):
        items = self._group(iterable)
        return self._pool.map(func, items, chunksize)

    def map_async(self, func, iterable, chunksize=None, callback=None, error_callback=None):
        items = self._group(iterable)
        return self._pool.map_async(func, items, chunksize, callback, error_callback)

    def imap(self, func, iterable, chunksize=1):
        items = self._group(iterable)
        return self._pool.imap(func, items, chunksize)

    def imap_unordered(self, func, iterable, chunksize=1):
        items = self._group(iterable)
        return self._pool.imap_unordered(func, items, chunksize)

    def starmap(self, func, iterable, chunksize=None):
        items = self._group(iterable)
        return self._pool.starmap(func, items, chunksize)

    def starmap_async(self, func, iterable, chunksize=None, callback=None, error_callback=None):
        items = self._group(iterable)
        return self._pool.starmap_async(func, items, chunksize, callback, error_callback)

    def apply(self, func, args=(), kwds=None):
        submitted_individual.append(chunk_length(args))
        return self._pool.apply(func, args, {} if kwds is None else kwds)

    def apply_async(self, func, args=(), kwds=None, callback=None, error_callback=None):
        submitted_individual.append(chunk_length(args))
        return self._pool.apply_async(func, args, {} if kwds is None else kwds, callback, error_callback)

    def __enter__(self):
        self._pool.__enter__()
        return self

    def __exit__(self, *args):
        return self._pool.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._pool, name)

def pool_factory(*args, **kwargs):
    return SpyPool(*args, **kwargs)

multiprocessing.Pool = pool_factory
multiprocessing.pool.Pool = pool_factory

runpy.run_path(SIMULATE, run_name="__main__")

assert 4 in pool_sizes, f"Expected multiprocessing.Pool with 4 workers; observed {pool_sizes}"
grouped_correctly = any(group == [2500, 2500, 2500, 2500] for group in submitted_groups)
individual_correctly = submitted_individual == [2500, 2500, 2500, 2500]
assert grouped_correctly or individual_correctly, (
    "Expected exactly four equal 2500-element chunks to be submitted to the Pool; "
    f"groups={submitted_groups}, individual={submitted_individual}"
)
PY

cat > /tmp/run_regression_checked.py <<'PY'
import json
import os
import runpy
import numpy as np
import scipy.stats

REFERENCE_PATH = os.path.realpath("/home/user/reference.npy")
OUTPUT_PATH = os.path.realpath("/home/user/output_fast.npy")
REPORT_PATH = "/home/user/report.json"

real_load = np.load
real_ks = scipy.stats.ks_2samp
loaded_paths = []
ks_calls = []

def tracked_load(file, *args, **kwargs):
    path = os.path.realpath(os.fspath(file))
    loaded_paths.append(path)
    return real_load(file, *args, **kwargs)

def tracked_ks(a, b, *args, **kwargs):
    ks_calls.append((np.asarray(a).copy(), np.asarray(b).copy()))
    return real_ks(a, b, *args, **kwargs)

np.load = tracked_load
scipy.stats.ks_2samp = tracked_ks
runpy.run_path("/home/user/test_regression.py", run_name="__main__")

assert REFERENCE_PATH in loaded_paths, "test_regression.py did not load /home/user/reference.npy"
assert OUTPUT_PATH in loaded_paths, "test_regression.py did not load /home/user/output_fast.npy"
assert ks_calls, "test_regression.py did not call scipy.stats.ks_2samp"

reference = real_load(REFERENCE_PATH)
output = real_load(OUTPUT_PATH)
assert any(
    (np.array_equal(a, reference) and np.array_equal(b, output)) or
    (np.array_equal(a, output) and np.array_equal(b, reference))
    for a, b in ks_calls
), "ks_2samp was not called with the loaded reference and optimized output arrays"

with open(REPORT_PATH, "r") as f:
    report = json.load(f)
expected_p = float(real_ks(reference, output).pvalue)
assert set(report) == {"p_value", "passed"}, f"Unexpected report structure: {report}"
assert type(report["p_value"]) in (int, float), "p_value must be numeric"
assert type(report["passed"]) is bool, "passed must be a JSON boolean"
assert float(report["p_value"]) == expected_p, (report["p_value"], expected_p)
assert report["passed"] is (expected_p > 0.99)
PY

cat > /tmp/check_final_state.py <<'PY'
import json
import os
import runpy
import numpy as np

output_path = "/home/user/output_fast.npy"
report_path = "/home/user/report.json"
simulate_path = "/home/user/simulate.py"
test_path = "/home/user/test_regression.py"
reference_path = "/home/user/reference.npy"

assert os.path.isfile(output_path), f"Expected file {output_path} to exist."
assert os.path.isfile(report_path), f"Expected file {report_path} to exist."
assert os.path.isfile(simulate_path), f"Expected file {simulate_path} to exist."
assert os.path.isfile(test_path), f"Expected file {test_path} to exist."

with open(report_path, "r") as f:
    report = json.load(f)
assert "passed" in report, f"Key 'passed' missing in {report_path}."
assert "p_value" in report, f"Key 'p_value' missing in {report_path}."
assert report["passed"] is True, f"Expected 'passed' to be True, got {report['passed']}."
assert report["p_value"] == 1.0, f"Expected 'p_value' to be 1.0, got {report['p_value']}."

with open(simulate_path, "r") as f:
    simulate_source = f.read()
assert "multiprocessing" in simulate_source, f"Expected to find 'multiprocessing' in {simulate_path}."

with open(test_path, "r") as f:
    test_source = f.read()
assert "ks_2samp" in test_source, "Regression script must use scipy.stats.ks_2samp"
assert "/home/user/reference.npy" in test_source
assert "/home/user/output_fast.npy" in test_source

reference = np.load(reference_path)
output = np.load(output_path)
assert output.shape == reference.shape, (output.shape, reference.shape)
assert output.dtype == reference.dtype, (output.dtype, reference.dtype)
assert np.array_equal(output, reference), "output_fast.npy does not match the ground truth in value/order"

namespace = runpy.run_path(simulate_path, run_name="simulation_function_check")
assert callable(namespace.get("compute_spectrum")), "compute_spectrum is missing or not callable"
x = np.array([0.037, 0.413, 2.007, 7.333, 21.125, 49.91], dtype=float)
expected = np.zeros_like(x)
for i in range(len(x)):
    val = 0.0
    for j in range(50):
        val += np.sin(x[i] * j) * np.exp(-((x[i] - j) / 0.1) ** 2)
    expected[i] = val
actual = namespace["compute_spectrum"](x.copy())
assert np.allclose(actual, expected, rtol=1e-13, atol=1e-15), "compute_spectrum mathematics changed"
PY

if timeout 180s python3 /tmp/run_simulation_checked.py \
   && test -s /home/user/output_fast.npy \
   && timeout 60s python3 /tmp/run_regression_checked.py \
   && timeout 60s python3 /tmp/check_final_state.py; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
