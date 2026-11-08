#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import hashlib
import json
import math
import multiprocessing
import os
import pstats
import runpy
from concurrent import futures

SCRIPT = '/home/user/mc_laplace.py'
RESULTS = '/home/user/results.json'
PROFILE = '/home/user/profile.prof'
REFERENCE = '/home/user/reference_data.csv'
RECORDED = []

class ImmediateResult:
    def __init__(self, value):
        self.value = value
    def get(self, timeout=None):
        return self.value
    def wait(self, timeout=None):
        return None
    def ready(self):
        return True
    def successful(self):
        return True

class RecordingPool:
    def __init__(self, *args, **kwargs):
        pass
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return False
    def close(self):
        pass
    def join(self):
        pass
    def terminate(self):
        pass
    def map(self, fn, iterable, chunksize=None):
        items = list(iterable)
        values = [fn(item) for item in items]
        RECORDED.extend(zip(items, values))
        return values
    def starmap(self, fn, iterable, chunksize=None):
        items = list(iterable)
        values = [fn(*item) for item in items]
        RECORDED.extend(zip(items, values))
        return values
    def imap(self, fn, iterable, chunksize=1):
        return iter(self.map(fn, iterable, chunksize))
    def imap_unordered(self, fn, iterable, chunksize=1):
        return iter(self.map(fn, iterable, chunksize))
    def map_async(self, fn, iterable, chunksize=None, callback=None, error_callback=None):
        try:
            value = self.map(fn, iterable, chunksize)
            if callback:
                callback(value)
            return ImmediateResult(value)
        except Exception as exc:
            if error_callback:
                error_callback(exc)
            raise
    def starmap_async(self, fn, iterable, chunksize=None, callback=None, error_callback=None):
        try:
            value = self.starmap(fn, iterable, chunksize)
            if callback:
                callback(value)
            return ImmediateResult(value)
        except Exception as exc:
            if error_callback:
                error_callback(exc)
            raise
    def apply(self, fn, args=(), kwds=None):
        kwds = kwds or {}
        value = fn(*args, **kwds)
        RECORDED.append((args, value))
        return value
    def apply_async(self, fn, args=(), kwds=None, callback=None, error_callback=None):
        try:
            value = self.apply(fn, args, kwds)
            if callback:
                callback(value)
            return ImmediateResult(value)
        except Exception as exc:
            if error_callback:
                error_callback(exc)
            raise

class RecordingExecutor:
    def __init__(self, *args, **kwargs):
        pass
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return False
    def shutdown(self, wait=True, cancel_futures=False):
        pass
    def map(self, fn, *iterables, timeout=None, chunksize=1):
        items = list(zip(*iterables))
        values = []
        for item in items:
            value = fn(*item)
            RECORDED.append((item if len(item) != 1 else item[0], value))
            values.append(value)
        return iter(values)
    def submit(self, fn, *args, **kwargs):
        future = futures.Future()
        try:
            value = fn(*args, **kwargs)
            RECORDED.append((args, value))
            future.set_result(value)
        except BaseException as exc:
            future.set_exception(exc)
        return future

def coordinate(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    value = float(value)
    if value.is_integer() and 1 <= value <= 19:
        return int(value)
    scaled = value * 20.0
    if 0.0 < value < 1.0 and abs(scaled - round(scaled)) < 1e-8 and 1 <= round(scaled) <= 19:
        return int(round(scaled))
    return None

def extract_coord(obj):
    if isinstance(obj, dict):
        if 'i' in obj and 'j' in obj:
            a, b = coordinate(obj['i']), coordinate(obj['j'])
            if a is not None and b is not None:
                return a, b
        if 'x' in obj and 'y' in obj:
            a, b = coordinate(obj['x']), coordinate(obj['y'])
            if a is not None and b is not None:
                return a, b
    if isinstance(obj, (tuple, list)):
        if len(obj) >= 2:
            a, b = coordinate(obj[0]), coordinate(obj[1])
            if a is not None and b is not None:
                return a, b
        for part in obj:
            found = extract_coord(part)
            if found is not None:
                return found
    return None

def extract_temperature(obj):
    if isinstance(obj, dict):
        for key in ('temperature', 'temp', 'estimate', 'value', 'u'):
            if key in obj:
                return extract_temperature(obj[key])
        return None
    if isinstance(obj, bool):
        return None
    if isinstance(obj, (int, float)):
        value = float(obj)
        return value if math.isfinite(value) else None
    if isinstance(obj, (tuple, list)):
        nums = [float(v) for v in obj if isinstance(v, (int, float)) and not isinstance(v, bool)]
        if len(nums) >= 4 and nums[-1] in (500.0, 2000.0):
            if 0.0 <= nums[-2] <= 1.0:
                return nums[-2]
            if 0.0 <= nums[-2] / nums[-1] <= 1.0:
                return nums[-2] / nums[-1]
        if nums:
            return nums[-1]
    return None

def explicit_walk_count(item):
    if isinstance(item, dict):
        for key in ('walks', 'n_walks', 'num_walks', 'W', 'w'):
            if key in item and item[key] in (500, 2000):
                return int(item[key])
    if isinstance(item, (tuple, list)):
        for value in item:
            if isinstance(value, (tuple, list, dict)):
                nested = explicit_walk_count(value)
                if nested is not None:
                    return nested
            elif not isinstance(value, bool) and value in (500, 2000):
                return int(value)
    return None

def test_mc_laplace_script():
    assert os.path.exists(SCRIPT), f'{SCRIPT} does not exist.'
    with open(SCRIPT, 'r') as f:
        code = f.read()
    assert 'multiprocessing' in code or 'ProcessPoolExecutor' in code, 'Script must use multiprocessing.'
    assert 'cProfile' in code or 'profile' in code.lower(), 'Script must use cProfile.'

    tree = ast.parse(code, filename=SCRIPT)
    literals = {node.value for node in ast.walk(tree) if isinstance(node, ast.Constant) and isinstance(node.value, (int, float))}
    assert 500 in literals and 2000 in literals, 'Both required walk counts must be implemented.'

    before_hash = hashlib.sha256(open(REFERENCE, 'rb').read()).hexdigest()
    for path in (RESULTS, PROFILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    multiprocessing.Pool = RecordingPool
    try:
        import multiprocessing.context
        multiprocessing.context.BaseContext.Pool = lambda self, *a, **k: RecordingPool(*a, **k)
    except Exception:
        pass
    futures.ProcessPoolExecutor = RecordingExecutor

    try:
        runpy.run_path(SCRIPT, run_name='__main__')
    except SystemExit as exc:
        assert exc.code in (None, 0), f'Script exited unsuccessfully: {exc.code}'

    assert hashlib.sha256(open(REFERENCE, 'rb').read()).hexdigest() == before_hash, 'Script modified reference_data.csv.'
    assert RECORDED, 'No work was submitted through a multiprocessing pool or process executor.'

    estimates = {}
    explicit_counts = {}
    for item, output in RECORDED:
        point = extract_coord(item) or extract_coord(output)
        value = extract_temperature(output)
        if point is not None and value is not None and 0.0 <= value <= 1.0:
            estimates[point] = value
            count = explicit_walk_count(item)
            if count is not None:
                explicit_counts[point] = count

    expected_points = {(i, j) for i in range(1, 20) for j in range(1, 20)}
    assert set(estimates) == expected_points, 'Parallel workers must return an estimate for every one of the 361 interior grid points.'

    if explicit_counts:
        assert set(explicit_counts) == expected_points, 'Walk counts must be supplied consistently for every interior point.'
        for (i, j), count in explicit_counts.items():
            expected = 2000 if 5 <= i <= 15 and 5 <= j <= 15 else 500
            assert count == expected, f'Wrong walk count at ({i}, {j}): got {count}, expected {expected}.'

    exact_max = max(
        abs(value - (math.sinh(math.pi * (1.0 - j / 20.0)) / math.sinh(math.pi)) * math.sin(math.pi * i / 20.0))
        for (i, j), value in estimates.items()
    )

    reference = {}
    with open(REFERENCE, newline='') as f:
        for row in csv.DictReader(f):
            i = int(round(float(row['x']) * 20))
            j = int(round(float(row['y']) * 20))
            reference[(i, j)] = float(row['temperature'])
    assert set(reference) == expected_points, 'Reference dataset does not contain the expected interior grid.'
    exact_mse = sum((estimates[p] - reference[p]) ** 2 for p in expected_points) / len(expected_points)

    assert os.path.exists(RESULTS), f'{RESULTS} does not exist.'
    with open(RESULTS) as f:
        results = json.load(f)
    assert set(results) == {'max_abs_error', 'mse_reference', 'execution_time'}, 'results.json must contain exactly the required keys.'
    for key in results:
        assert isinstance(results[key], (int, float)) and not isinstance(results[key], bool), f'{key} must be a number.'
        assert math.isfinite(results[key]), f'{key} must be finite.'
    assert results['max_abs_error'] >= 0, 'max_abs_error cannot be negative.'
    assert results['mse_reference'] >= 0, 'mse_reference cannot be negative.'
    assert results['execution_time'] > 0, 'execution_time must be positive.'
    assert results['max_abs_error'] < 0.08, f"max_abs_error is too high: {results['max_abs_error']} >= 0.08"
    assert results['mse_reference'] < 0.05, f"mse_reference is too high: {results['mse_reference']} >= 0.05"
    assert math.isclose(results['max_abs_error'], exact_max, rel_tol=1e-7, abs_tol=1e-9), 'Reported max_abs_error was not computed from the returned grid estimates.'
    assert math.isclose(results['mse_reference'], exact_mse, rel_tol=1e-7, abs_tol=1e-10), 'Reported mse_reference was not computed from the returned grid estimates and reference data.'

def test_profile_output():
    assert os.path.exists(PROFILE), f'{PROFILE} does not exist.'
    try:
        stats = pstats.Stats(PROFILE)
    except Exception as exc:
        assert False, f'Failed to read {PROFILE} as a valid cProfile dump: {exc}'
    assert stats.total_calls > 0, 'Profile stats indicate no calls were recorded.'
    script_entries = [(key, data) for key, data in stats.stats.items() if os.path.abspath(key[0]) == SCRIPT]
    assert any(key[2] == 'main' for key, _ in script_entries), 'The profile must include mc_laplace.py main().'
    assert sum(data[1] for _, data in script_entries) >= 362, 'The profile does not show the complete grid computation inside main().'
TEST_EOF

if timeout 240s python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
