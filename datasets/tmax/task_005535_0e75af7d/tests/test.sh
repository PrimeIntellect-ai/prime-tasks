#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import concurrent.futures
import ctypes
import importlib
import importlib.machinery
import json
import os
import runpy
import shutil
import subprocess
import sys
import threading
import types

import pytest

PIPELINE = '/home/user/pipeline'
DATA_DIR = os.path.join(PIPELINE, 'data')
RESULTS_PATH = os.path.join(PIPELINE, 'final_results.json')


def legacy_multiplier():
    library = ctypes.CDLL(os.path.join(PIPELINE, 'liblegacy.so'))
    library.get_multiplier.argtypes = []
    library.get_multiplier.restype = ctypes.c_int
    return library.get_multiplier()


def expected_results(multiplier):
    expected = {}
    for i in range(500):
        filename = f'file_{i}.json'
        filepath = os.path.join(DATA_DIR, filename)
        assert os.path.isfile(filepath), f'Data file {filepath} is missing.'
        with open(filepath, 'r') as f:
            data = json.load(f)
        values = data.get('values', [])
        expected[filename] = multiplier * sum(
            val * (idx + 1) for idx, val in enumerate(values)
        )
    return expected


def validate_final_results(expected):
    assert os.path.isfile(RESULTS_PATH), (
        f'{RESULTS_PATH} is missing. Did you run query_data.py?'
    )
    try:
        with open(RESULTS_PATH, 'r') as f:
            results = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'Could not parse {RESULTS_PATH} as JSON.')

    assert isinstance(results, dict), (
        'final_results.json must contain a JSON dictionary.'
    )
    assert len(results) == 500, (
        f'Expected exactly 500 keys in final_results.json, got {len(results)}. '
        'The race condition may not be fully fixed.'
    )

    for i in range(500):
        filename = f'file_{i}.json'
        assert filename in results, (
            f"'{filename}' is missing from final_results.json."
        )
        actual_score = results[filename]
        expected_score = expected[filename]
        assert actual_score == expected_score, (
            f'Incorrect score for {filename}. Expected {expected_score}, but got '
            f'{actual_score}. Check that fast_math.c implements the required '
            'formula and uses the multiplier from liblegacy.so.'
        )


def assert_original_rmw_is_synchronized_or_removed(source):
    tree = ast.parse(source)
    parents = {}
    for node in ast.walk(tree):
        for child in ast.iter_child_nodes(node):
            parents[child] = node

    def ancestors(node):
        result = []
        while node in parents:
            node = parents[node]
            result.append(node)
        return result

    for function in [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]:
        reads = []
        writes = []
        for node in ast.walk(function):
            if isinstance(node, ast.Assign) and any(
                isinstance(target, ast.Name) and target.id == 'current'
                for target in node.targets
            ):
                value = node.value
                if (
                    isinstance(value, ast.Call)
                    and isinstance(value.func, ast.Attribute)
                    and value.func.attr == 'get'
                    and isinstance(value.func.value, ast.Name)
                    and value.func.value.id == 'results'
                ):
                    reads.append(node)
            if isinstance(node, ast.Assign) and any(
                isinstance(target, ast.Subscript)
                and isinstance(target.value, ast.Name)
                and target.value.id == 'results'
                for target in node.targets
            ):
                if any(
                    isinstance(part, ast.Name) and part.id == 'current'
                    for part in ast.walk(node.value)
                ):
                    writes.append(node)

        if not reads or not writes:
            continue

        calls = [
            n.func.attr
            for n in ast.walk(function)
            if isinstance(n, ast.Call)
            and isinstance(n.func, ast.Attribute)
            and n.func.attr in {'acquire', 'release'}
        ]
        explicit_locking = 'acquire' in calls and 'release' in calls

        for read in reads:
            for write in writes:
                read_with = {n for n in ancestors(read) if isinstance(n, ast.With)}
                write_with = {n for n in ancestors(write) if isinstance(n, ast.With)}
                protected_by_with = bool(read_with & write_with)
                assert protected_by_with or explicit_locking, (
                    'query_data.py still contains the original unsynchronized '
                    'results.get/read-modify-write aggregation.'
                )


def test_repaired_pipeline_builds_and_runs_reliably():
    assert os.path.isdir(DATA_DIR), f'{DATA_DIR} directory is missing.'
    for required in ('fast_math.c', 'setup.py', 'query_data.py', 'liblegacy.so'):
        path = os.path.join(PIPELINE, required)
        assert os.path.isfile(path), f'{path} is missing.'

    query_path = os.path.join(PIPELINE, 'query_data.py')
    with open(query_path, 'r') as f:
        query_source = f.read()
    assert_original_rmw_is_synchronized_or_removed(query_source)

    # Remove prior build products so setup.py and fast_math.c must build now.
    shutil.rmtree(os.path.join(PIPELINE, 'build'), ignore_errors=True)
    for name in os.listdir(PIPELINE):
        if name.startswith('fast_math') and any(
            name.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES
        ):
            os.remove(os.path.join(PIPELINE, name))

    build = subprocess.run(
        [sys.executable, 'setup.py', 'build_ext', '--inplace'],
        cwd=PIPELINE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert build.returncode == 0, f'Extension build failed:\n{build.stdout}'

    sys.path.insert(0, PIPELINE)
    try:
        importlib.invalidate_caches()
        sys.modules.pop('fast_math', None)
        fast_math = importlib.import_module('fast_math')
        origin = os.path.realpath(fast_math.__spec__.origin)
        assert any(origin.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), (
            f'fast_math must be a compiled Python extension, not {origin}'
        )

        multiplier = legacy_multiplier()
        probes = [[], [7], [2, 5, 11], [-3, 0, 4, 9], list(range(1, 31))]
        for values in probes:
            expected = multiplier * sum(v * (i + 1) for i, v in enumerate(values))
            assert fast_math.calculate_score(values) == expected
    finally:
        if sys.path and sys.path[0] == PIPELINE:
            sys.path.pop(0)
        sys.modules.pop('fast_math', None)

    # Execute query_data.py with an instrumented fast_math module. This proves
    # that every file is actually routed through calculate_score and aggregated.
    fake = types.ModuleType('fast_math')
    call_count = 0
    call_lock = threading.Lock()

    def fake_calculate_score(values):
        nonlocal call_count
        with call_lock:
            call_count += 1
        return -(1_000_003 + sum((i + 3) * v for i, v in enumerate(values)))

    fake.calculate_score = fake_calculate_score
    sys.modules['fast_math'] = fake
    old_cwd = os.getcwd()
    try:
        os.chdir(PIPELINE)
        runpy.run_path(query_path, run_name='__main__')
    finally:
        os.chdir(old_cwd)
        sys.modules.pop('fast_math', None)

    assert call_count == 500, (
        f'query_data.py called fast_math.calculate_score {call_count} times; expected 500.'
    )
    with open(RESULTS_PATH, 'r') as f:
        instrumented_results = json.load(f)
    assert len(instrumented_results) == 500
    for i in range(500):
        filename = f'file_{i}.json'
        with open(os.path.join(DATA_DIR, filename), 'r') as f:
            values = json.load(f)['values']
        expected_fake = -(1_000_003 + sum((j + 3) * v for j, v in enumerate(values)))
        assert instrumented_results.get(filename) == expected_fake

    # Run the real pipeline repeatedly and preserve the original complete and
    # exact final-results assertions on every execution.
    expected = expected_results(legacy_multiplier())
    for attempt in range(4):
        run = subprocess.run(
            [sys.executable, 'query_data.py'],
            cwd=PIPELINE,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=120,
        )
        assert run.returncode == 0, (
            f'query_data.py failed on run {attempt + 1}:\n{run.stdout}'
        )
        validate_final_results(expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
