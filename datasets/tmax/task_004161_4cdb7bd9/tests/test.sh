#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

import pytest

SCRIPT = Path('/home/user/metric_porter.py')
CSV_PATH = Path('/home/user/legacy_metrics.csv')
OUTPUT = Path('/home/user/migrated_metrics.json')


def assert_original_output():
    file_path = '/home/user/migrated_metrics.json'
    assert os.path.exists(file_path), f'The file {file_path} does not exist.'
    assert os.path.isfile(file_path), f'{file_path} is not a file.'

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'The file {file_path} does not contain valid JSON.')

    expected = [
        {'ts': 1600000000, 'metrics': {'cpu': 10.0, 'mem': 80.1}, 'stats': {'cpu_sma_3': 10.0, 'cpu_var_3': 0.0}},
        {'ts': 1600000060, 'metrics': {'cpu': 20.0, 'mem': 81.0}, 'stats': {'cpu_sma_3': 15.0, 'cpu_var_3': 25.0}},
        {'ts': 1600000120, 'metrics': {'cpu': 30.0, 'mem': 82.5}, 'stats': {'cpu_sma_3': 20.0, 'cpu_var_3': 66.6667}},
        {'ts': 1600000180, 'metrics': {'cpu': 20.0, 'mem': 80.0}, 'stats': {'cpu_sma_3': 23.3333, 'cpu_var_3': 22.2222}},
        {'ts': 1600000240, 'metrics': {'cpu': 10.0, 'mem': 79.5}, 'stats': {'cpu_sma_3': 20.0, 'cpu_var_3': 66.6667}},
    ]

    assert isinstance(data, list), 'The JSON output should be a list of objects.'
    assert len(data) == len(expected), f'Expected {len(expected)} elements, but got {len(data)}.'
    for i, (actual_item, expected_item) in enumerate(zip(data, expected)):
        assert actual_item == expected_item, f'Mismatch at index {i}. Expected {expected_item}, but got {actual_item}.'


def inspect_script():
    assert SCRIPT.exists(), f'The file {SCRIPT} does not exist.'
    assert SCRIPT.is_file(), f'{SCRIPT} is not a file.'

    source = SCRIPT.read_text(encoding='utf-8')
    try:
        tree = ast.parse(source, filename=str(SCRIPT))
        compile(tree, str(SCRIPT), 'exec')
    except (SyntaxError, ValueError) as exc:
        pytest.fail(f'{SCRIPT} is not valid Python: {exc}')

    classes = [n for n in ast.walk(tree) if isinstance(n, ast.ClassDef) and n.name == 'TimeSeriesRingBuffer']
    assert classes, 'metric_porter.py must define TimeSeriesRingBuffer.'

    class UseVisitor(ast.NodeVisitor):
        def __init__(self):
            self.used = False

        def visit_ClassDef(self, node):
            if node.name != 'TimeSeriesRingBuffer':
                self.generic_visit(node)

        def visit_Call(self, node):
            if isinstance(node.func, ast.Name) and node.func.id == 'TimeSeriesRingBuffer':
                self.used = True
            self.generic_visit(node)

    visitor = UseVisitor()
    visitor.visit(tree)
    assert visitor.used, 'TimeSeriesRingBuffer must be instantiated by the processing implementation.'

    stdlib = set(sys.stdlib_module_names) | set(sys.builtin_module_names) | {'__future__'}
    statistics_aliases = set()
    statistics_modules = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                root = alias.name.split('.')[0]
                assert root in stdlib, f'Third-party import is not allowed: {alias.name}'
                if alias.name == 'statistics':
                    statistics_modules.add(alias.asname or 'statistics')
        elif isinstance(node, ast.ImportFrom):
            root = (node.module or '').split('.')[0]
            assert node.level == 0 and root in stdlib, f'Third-party or local import is not allowed: {node.module}'
            if node.module == 'statistics':
                for alias in node.names:
                    assert alias.name != '*', 'Wildcard statistics imports are not allowed.'
                    if alias.name in {'variance', 'pvariance'}:
                        statistics_aliases.add(alias.asname or alias.name)

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in statistics_aliases:
            pytest.fail('statistics variance functions may not be used.')
        if (isinstance(node.func, ast.Attribute)
                and node.func.attr in {'variance', 'pvariance'}
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id in statistics_modules):
            pytest.fail('statistics variance functions may not be used.')


def expected_for(rows):
    result = []
    window = []
    for ts, cpu, mem in rows:
        window.append(cpu)
        if len(window) > 3:
            window.pop(0)
        sma = sum(window) / len(window)
        variance = sum((x - sma) ** 2 for x in window) / len(window)
        result.append({
            'ts': ts,
            'metrics': {'cpu': round(float(cpu), 4), 'mem': round(float(mem), 4)},
            'stats': {'cpu_sma_3': round(float(sma), 4), 'cpu_var_3': round(float(variance), 4)},
        })
    return result


def assert_schema_and_values(actual, expected):
    assert isinstance(actual, list), 'The generated JSON must be an array.'
    assert len(actual) == len(expected)
    for index, (item, wanted) in enumerate(zip(actual, expected)):
        assert type(item) is dict, f'Row {index} must be an object.'
        assert set(item) == {'ts', 'metrics', 'stats'}, f'Wrong top-level schema at row {index}.'
        assert type(item['ts']) is int, f'ts must be an integer at row {index}.'
        assert type(item['metrics']) is dict and set(item['metrics']) == {'cpu', 'mem'}
        assert type(item['stats']) is dict and set(item['stats']) == {'cpu_sma_3', 'cpu_var_3'}
        for value in (item['metrics']['cpu'], item['metrics']['mem'], item['stats']['cpu_sma_3'], item['stats']['cpu_var_3']):
            assert type(value) is float, f'All metric and statistic values must be JSON floats at row {index}.'
        assert item == wanted, f'Mismatch at row {index}: expected {wanted}, got {item}'


def test_complete_solution():
    # Preserve all assertions made by the original verifier before changing its fixture.
    assert_original_output()
    inspect_script()

    original_csv = CSV_PATH.read_bytes()
    original_output = OUTPUT.read_bytes()
    rng = secrets.SystemRandom()
    base = 1700000000 + rng.randrange(100000)
    cpus = [rng.randrange(5, 951) / 10.0 for _ in range(8)]
    mems = [rng.randrange(100, 991) / 10.0 for _ in range(8)]
    rows = [(base + i * 47, cpus[i], mems[i]) for i in range(8)]

    try:
        with CSV_PATH.open('w', newline='', encoding='utf-8') as handle:
            writer = csv.writer(handle)
            writer.writerow(['timestamp', 'cpu_util', 'memory_util'])
            writer.writerows(rows)
        if OUTPUT.exists():
            OUTPUT.unlink()

        try:
            completed = subprocess.run(
                [sys.executable, str(SCRIPT)],
                cwd='/home/user',
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
        except subprocess.TimeoutExpired:
            pytest.fail('metric_porter.py did not finish within 15 seconds.')

        assert completed.returncode == 0, f'metric_porter.py failed:\n{completed.stderr}'
        assert OUTPUT.exists() and OUTPUT.is_file(), 'Executing metric_porter.py did not create migrated_metrics.json.'
        try:
            with OUTPUT.open('r', encoding='utf-8') as handle:
                actual = json.load(handle)
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            pytest.fail(f'Generated output is not valid JSON: {exc}')

        assert_schema_and_values(actual, expected_for(rows))
    finally:
        CSV_PATH.write_bytes(original_csv)
        OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
