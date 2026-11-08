#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

import pandas as pd
import pytest

HOME = Path('/home/user')
PARQUET = HOME / 'clean_sensor_data.parquet'
RESULTS = HOME / 'results.json'
RAW = HOME / 'raw_sensor_data.csv'
ID_RE = re.compile(r'^SENS-\d{4}$')


def const_int(node, constants):
    if isinstance(node, ast.Constant) and isinstance(node.value, int) and not isinstance(node.value, bool):
        return node.value
    if isinstance(node, ast.Name):
        return constants.get(node.id)
    return None


def call_name(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        base = call_name(node.value)
        return f'{base}.{node.attr}' if base else None
    return None


def benchmark_loops(path):
    try:
        tree = ast.parse(path.read_text(encoding='utf-8'))
    except Exception:
        return []
    constants = {}
    for node in tree.body:
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            val = const_int(value, constants)
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if val is not None:
                for target in targets:
                    if isinstance(target, ast.Name):
                        constants[target.id] = val
    found = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.For) or not isinstance(node.iter, ast.Call):
            continue
        if call_name(node.iter.func) != 'range':
            continue
        vals = [const_int(arg, constants) for arg in node.iter.args]
        count = None
        if len(vals) == 1 and vals[0] is not None:
            count = len(range(vals[0]))
        elif len(vals) == 2 and None not in vals:
            count = len(range(vals[0], vals[1]))
        elif len(vals) == 3 and None not in vals and vals[2] != 0:
            count = len(range(vals[0], vals[1], vals[2]))
        if count != 10000:
            continue
        calls = []
        for statement in node.body:
            for child in ast.walk(statement):
                if isinstance(child, ast.Call):
                    name = call_name(child.func)
                    if name:
                        calls.append(name)
        found.append(calls)
    return found


def probe_functions(script, names):
    probe = r'''
import json, math, runpy, sys, time
script = sys.argv[1]
names = json.loads(sys.argv[2])
sys.path.insert(0, '/home/user')
try:
    ns = runpy.run_path(script, run_name='__main__')
except SystemExit as e:
    if e.code not in (None, 0):
        raise

def resolve(name):
    parts = name.split('.')
    obj = ns.get(parts[0])
    for part in parts[1:]:
        obj = getattr(obj, part)
    return obj

def pair(result):
    if isinstance(result, dict):
        for mk, vk in [('posterior_mean','posterior_variance'), ('mean','variance'), ('mu','var')]:
            if mk in result and vk in result:
                return float(result[mk]), float(result[vk])
    if hasattr(result, 'tolist'):
        result = result.tolist()
    if isinstance(result, (tuple, list)) and len(result) >= 2:
        return float(result[0]), float(result[1])
    raise ValueError('not a mean/variance pair')

def invoke(fn, values):
    errors = []
    for args in [(values,), (values, 0.0, 10.0, 2.0)]:
        try:
            return fn(*args), args
        except Exception as e:
            errors.append(e)
    raise errors[-1]

matched = None
measured = None
for name in names:
    try:
        fn = resolve(name)
        if not callable(fn):
            continue
        r1, args1 = invoke(fn, [2.0, 4.0])
        r2, _ = invoke(fn, [-3.0, 1.0, 2.0, 5.0])
        p1, p2 = pair(r1), pair(r2)
        expected1 = (3.0 / 1.1, 1.0 / 1.1)
        expected2 = (2.5 / 2.1, 1.0 / 2.1)
        if not all(math.isclose(a, b, rel_tol=1e-8, abs_tol=1e-8)
                   for a, b in zip(p1 + p2, expected1 + expected2)):
            continue
        start = time.perf_counter()
        for _ in range(10000):
            fn(*args1)
        measured = (time.perf_counter() - start) * 1000.0 / 10000.0
        matched = name
        break
    except Exception:
        continue
print('__VERIFIER_PROBE__' + json.dumps({'matched': matched, 'measured_ms': measured}))
'''
    proc = subprocess.run(
        [sys.executable, '-c', probe, str(script), json.dumps(names)],
        cwd=str(HOME), text=True, capture_output=True, timeout=120
    )
    if proc.returncode != 0:
        return None
    marker = '__VERIFIER_PROBE__'
    lines = [line for line in proc.stdout.splitlines() if line.startswith(marker)]
    if not lines:
        return None
    return json.loads(lines[-1][len(marker):])


@pytest.fixture(scope='session')
def executed_pipeline():
    candidates = []
    for path in sorted(HOME.rglob('*.py')):
        loops = benchmark_loops(path)
        if loops:
            candidates.append((path, loops))
    assert candidates, 'No Python artifact containing an exactly 10,000-iteration benchmark loop was found'

    for path, loops in candidates:
        for output in (PARQUET, RESULTS):
            if output.exists():
                output.unlink()
        proc = subprocess.run(
            [sys.executable, str(path)], cwd=str(HOME), text=True,
            capture_output=True, timeout=120
        )
        if proc.returncode != 0 or not PARQUET.is_file() or not RESULTS.is_file():
            continue
        names = sorted(set(name for calls in loops for name in calls))
        probe = probe_functions(path, names)
        if not probe or not probe.get('matched'):
            continue
        matched = probe['matched']
        # The validated standalone update must be invoked exactly once by a
        # loop whose range contains exactly 10,000 iterations.
        if not any(calls.count(matched) == 1 for calls in loops):
            continue
        return {'path': str(path), 'measured_ms': float(probe['measured_ms'])}
    pytest.fail('No executable pipeline both produced the artifacts and benchmarked a valid standalone Bayesian update function')


def parse_iso(value):
    assert isinstance(value, str) and value, 'timestamp must be a nonempty ISO 8601 string'
    return datetime.fromisoformat(value[:-1] + '+00:00' if value.endswith('Z') else value)


def expected_rows():
    rows = []
    with RAW.open(newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            sid = row.get('sensor_id')
            timestamp = row.get('timestamp')
            raw = row.get('raw_value')
            try:
                if not isinstance(sid, str) or ID_RE.fullmatch(sid) is None:
                    continue
                parse_iso(timestamp)
                value = float(raw)
                if not math.isfinite(value) or not -10.0 <= value <= 10.0:
                    continue
            except (TypeError, ValueError, AssertionError):
                continue
            rows.append((sid, timestamp, value))
    return rows


def timestamp_key(value):
    if isinstance(value, str):
        dt = parse_iso(value)
    else:
        assert not pd.isna(value), 'Parquet timestamp contains null values'
        dt = pd.Timestamp(value).to_pydatetime()
    return dt.isoformat()


def test_parquet_file_exists(executed_pipeline):
    assert PARQUET.is_file(), f'Expected Parquet file missing at {PARQUET}'
    assert PARQUET.stat().st_size > 0, f'Parquet file {PARQUET} is empty'


def test_parquet_schema_and_rows(executed_pipeline):
    expected = expected_rows()
    assert len(expected) == 150, f'Expected 150 valid source rows, got {len(expected)}'
    try:
        frame = pd.read_parquet(PARQUET)
    except Exception as exc:
        pytest.fail(f'{PARQUET} is not a readable Parquet file: {exc}')

    assert list(frame.columns) == ['sensor_id', 'timestamp', 'raw_value'], 'Unexpected Parquet schema'
    assert len(frame) == len(expected), 'Parquet row count does not match validated raw CSV rows'
    assert frame['sensor_id'].map(lambda x: isinstance(x, str) and ID_RE.fullmatch(x) is not None).all()
    assert pd.api.types.is_float_dtype(frame['raw_value'].dtype), 'raw_value must have a floating-point Parquet type'
    assert frame['raw_value'].map(lambda x: math.isfinite(float(x)) and -10.0 <= float(x) <= 10.0).all()

    actual_records = Counter(
        (str(row.sensor_id), timestamp_key(row.timestamp), round(float(row.raw_value), 12))
        for row in frame.itertuples(index=False)
    )
    expected_records = Counter(
        (sid, timestamp_key(timestamp), round(value, 12))
        for sid, timestamp, value in expected
    )
    assert actual_records == expected_records, 'Parquet rows are not exactly the schema-valid rows from the raw CSV'


def test_results_json_exists(executed_pipeline):
    assert RESULTS.is_file(), f'Expected JSON summary missing at {RESULTS}'


def test_results_json_content(executed_pipeline):
    try:
        with RESULTS.open(encoding='utf-8') as f:
            results = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'File {RESULTS} is not valid JSON')

    required = {
        'valid_rows_count', 'SENS_0042_posterior_mean',
        'SENS_0042_posterior_variance', 'benchmark_avg_ms'
    }
    assert set(results) == required, f'results.json must contain exactly these keys: {sorted(required)}'

    expected = expected_rows()
    values = [value for sid, _, value in expected if sid == 'SENS-0042']
    precision = 1.0 / 10.0 + len(values) / 2.0
    expected_variance = 1.0 / precision
    expected_mean = (sum(values) / 2.0) / precision

    assert type(results['valid_rows_count']) is int, 'valid_rows_count must be an integer'
    assert results['valid_rows_count'] == 150, f"Expected 150 valid rows, got {results['valid_rows_count']}"

    mean_val = results['SENS_0042_posterior_mean']
    assert isinstance(mean_val, (int, float)) and not isinstance(mean_val, bool), 'Posterior mean must be a number'
    assert math.isfinite(float(mean_val))
    assert mean_val == round(expected_mean, 4), f'Incorrect posterior mean: {mean_val}'
    assert abs(mean_val - 1.4970) < 0.0001, f'Expected posterior mean ~1.4970, got {mean_val}'

    var_val = results['SENS_0042_posterior_variance']
    assert isinstance(var_val, (int, float)) and not isinstance(var_val, bool), 'Posterior variance must be a number'
    assert math.isfinite(float(var_val))
    assert var_val == round(expected_variance, 4), f'Incorrect posterior variance: {var_val}'
    assert abs(var_val - 0.0200) < 0.0001, f'Expected posterior variance ~0.0200, got {var_val}'

    benchmark = results['benchmark_avg_ms']
    assert isinstance(benchmark, (int, float)) and not isinstance(benchmark, bool), 'Benchmark time must be a number'
    assert math.isfinite(float(benchmark)) and benchmark >= 0, f'Benchmark time cannot be negative or non-finite, got {benchmark}'
    assert benchmark > 0, 'Benchmark time must be a measured positive duration'
    measured = executed_pipeline['measured_ms']
    ratio = float(benchmark) / measured
    assert 0.01 <= ratio <= 100.0, 'Reported benchmark is implausible for the submitted update function'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
