#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import subprocess
from pathlib import Path

import pytest

PROJECT = Path('/home/user/math_dag')
GRAPH = PROJECT / 'graph.json'
RESULTS = PROJECT / 'results.json'


def run(cmd, timeout=45):
    env = os.environ.copy()
    env['LD_LIBRARY_PATH'] = str(PROJECT)
    env['CGO_ENABLED'] = '1'
    return subprocess.run(
        cmd,
        cwd=PROJECT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=True,
    )


def run_program():
    RESULTS.unlink(missing_ok=True)
    run(['go', 'run', 'main.go'])
    assert RESULTS.is_file(), f'{RESULTS} is missing. Did the program run and generate the output?'
    try:
        with RESULTS.open() as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'{RESULTS} is not valid JSON')


def assert_original_results(results):
    expected = {
        'A': 10.0,
        'B': 5.0,
        'C': 15.0,
        'D': 150.0,
        'E': 75.0,
        'F': 225.0,
    }

    for key, expected_val in expected.items():
        assert key in results, f"Node '{key}' is missing from the results."
        actual_val = float(results[key])
        assert actual_val == expected_val, (
            f"Node '{key}' evaluated incorrectly. Expected {expected_val}, got {actual_val}."
        )


def evaluate(nodes):
    by_id = {node['id']: node for node in nodes}
    memo = {}

    def visit(node_id):
        if node_id in memo:
            return memo[node_id]
        node = by_id[node_id]
        if node['type'] == 'value':
            value = float(node['val'])
        else:
            left = visit(node['deps'][0])
            right = visit(node['deps'][1])
            value = left + right if node['type'] == 'add' else left * right
        memo[node_id] = value
        return value

    for node_id in by_id:
        visit(node_id)
    return memo


def test_completed_project():
    original_graph = GRAPH.read_bytes()
    try:
        build_source = (PROJECT / 'build.sh').read_text()
        assert '-fPIC' in build_source, 'build.sh must compile position-independent code with -fPIC'
        assert '-shared' in build_source, 'build.sh must create a shared library with -shared'

        for artifact in PROJECT.glob('*.o'):
            artifact.unlink()
        (PROJECT / 'libmathcore.so').unlink(missing_ok=True)
        run(['./build.sh'])

        library = PROJECT / 'libmathcore.so'
        assert library.is_file(), 'build.sh did not create libmathcore.so'
        elf = run(['readelf', '-h', str(library)]).stdout
        assert re.search(r'Type:\s+DYN', elf), 'libmathcore.so is not an ELF shared object'
        symbols = run(['nm', '-D', '--defined-only', str(library)]).stdout
        assert re.search(r'\bop_add\b', symbols), 'libmathcore.so does not export op_add'
        assert re.search(r'\bop_mul\b', symbols), 'libmathcore.so does not export op_mul'

        main_source = (PROJECT / 'main.go').read_text()
        assert re.search(r'import\s+"C"', main_source), 'main.go must use cgo'
        assert re.search(r'#cgo\s+LDFLAGS:[^\n]*-lmathcore\b', main_source), 'cgo must link libmathcore.so'
        assert re.search(r'\bC\s*\.\s*op_add\s*\(', main_source), 'main.go must call C.op_add'
        assert re.search(r'\bC\s*\.\s*op_mul\s*\(', main_source), 'main.go must call C.op_mul'
        assert re.search(r'\bgo\s+', main_source), 'DAG evaluation must launch goroutines'
        assert re.search(r'\bchan\b', main_source), 'DAG evaluation must use channels'

        # Preserve the original verifier's assertions after actually building and running.
        original_results = run_program()
        assert_original_results(original_results)

        suffix = secrets.token_hex(4)
        values = random.SystemRandom().sample(range(2, 30), 3)
        a, b, c = [f'value_{name}_{suffix}' for name in ('a', 'b', 'c')]
        add1, mul1, add2, mul2, root = [
            f'node_{name}_{suffix}' for name in ('add1', 'mul1', 'add2', 'mul2', 'root')
        ]
        nodes = [
            {'id': a, 'type': 'value', 'val': values[0]},
            {'id': b, 'type': 'value', 'val': values[1]},
            {'id': c, 'type': 'value', 'val': values[2]},
            {'id': add1, 'type': 'add', 'deps': [a, b]},
            {'id': mul1, 'type': 'mul', 'deps': [add1, c]},
            {'id': add2, 'type': 'add', 'deps': [b, c]},
            {'id': mul2, 'type': 'mul', 'deps': [add2, a]},
            {'id': root, 'type': 'add', 'deps': [mul1, mul2]},
        ]
        random.SystemRandom().shuffle(nodes)
        expected = evaluate(nodes)
        GRAPH.write_text(json.dumps(nodes))

        dynamic_results = run_program()
        assert isinstance(dynamic_results, dict), 'results.json must contain a flat JSON object'
        assert set(dynamic_results) == set(expected), 'results.json must contain every and only graph node IDs'
        for node_id, expected_value in expected.items():
            actual = dynamic_results[node_id]
            assert isinstance(actual, (int, float)) and not isinstance(actual, bool), (
                f"Result for '{node_id}' must be a JSON number"
            )
            assert float(actual) == expected_value, (
                f"Node '{node_id}' evaluated incorrectly. Expected {expected_value}, got {actual}."
            )
    finally:
        GRAPH.write_bytes(original_graph)
        try:
            restored_results = run_program()
            assert_original_results(restored_results)
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
