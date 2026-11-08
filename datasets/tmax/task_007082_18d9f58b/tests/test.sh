#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import secrets
import subprocess

import pytest

MESH_FILE = '/home/user/data/mesh.csv'
SOURCE_FILE = '/home/user/pipeline/process_mesh.go'
OUTPUT_FILE = '/home/user/pipeline/output.json'
EXECUTABLE = '/tmp/process_mesh_test'


def expected_stats(grid):
    q1 = [grid[r][c] for r in range(50) for c in range(50)]
    q4 = [grid[r][c] for r in range(50, 100) for c in range(50, 100)]
    n1, n4 = len(q1), len(q4)
    mean_q1 = sum(q1) / n1
    mean_q4 = sum(q4) / n4
    var_q1 = sum((x - mean_q1) ** 2 for x in q1) / (n1 - 1)
    var_q4 = sum((x - mean_q4) ** 2 for x in q4) / (n4 - 1)
    t_stat = (mean_q1 - mean_q4) / math.sqrt(var_q1 / n1 + var_q4 / n4)
    num = (var_q1 / n1 + var_q4 / n4) ** 2
    den = ((var_q1 / n1) ** 2) / (n1 - 1) + ((var_q4 / n4) ** 2) / (n4 - 1)
    return {
        'mean_q1': mean_q1,
        'mean_q4': mean_q4,
        'var_q1': var_q1,
        'var_q4': var_q4,
        't_stat': t_stat,
        'df': num / den,
    }


def validate_output(expected):
    assert os.path.isfile(OUTPUT_FILE), f'Output file {OUTPUT_FILE} is missing.'
    try:
        with open(OUTPUT_FILE, 'r') as f:
            actual = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'File {OUTPUT_FILE} is not valid JSON.')

    for key, expected_val in expected.items():
        assert key in actual, f"Missing key '{key}' in {OUTPUT_FILE}."
        actual_val = actual[key]
        assert isinstance(actual_val, (int, float)), f"Value for '{key}' must be a float."
        assert math.isclose(actual_val, expected_val, rel_tol=1e-4, abs_tol=1e-4), \
            f"Value for '{key}' is incorrect. Expected {expected_val}, got {actual_val}."


def run_program():
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    result = subprocess.run(
        [EXECUTABLE], cwd='/home/user/pipeline', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, \
        f'Compiled Go program failed. stdout={result.stdout!r} stderr={result.stderr!r}'
    assert os.path.isfile(OUTPUT_FILE), 'The Go program did not generate output.json.'


def test_final_state():
    assert os.path.isfile(MESH_FILE), f'Data file {MESH_FILE} is missing.'
    assert os.path.isfile(SOURCE_FILE), f'Go source file {SOURCE_FILE} is missing.'

    with open(SOURCE_FILE, 'r', encoding='utf-8') as f:
        source = f.read()
    code = re.sub(r'//.*|/\*.*?\*/|"(?:\\.|[^"\\])*"|`[^`]*`', ' ', source,
                  flags=re.MULTILINE | re.DOTALL)
    assert re.search(r'\bgo\s+', code), 'process_mesh.go does not launch a Go goroutine.'
    assert re.search(r'\bchan\b|\bsync\s*\.\s*WaitGroup\b', code), \
        'process_mesh.go lacks channel or WaitGroup synchronization for concurrent work.'

    build = subprocess.run(
        ['go', 'build', '-o', EXECUTABLE, SOURCE_FILE], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert build.returncode == 0, \
        f'process_mesh.go does not compile. stdout={build.stdout!r} stderr={build.stderr!r}'

    with open(MESH_FILE, 'rb') as f:
        original_mesh = f.read()

    try:
        # Exercise the compiled artifact on verifier-generated meshes so stale or
        # precomputed output cannot pass.
        for trial in range(2):
            rng = random.Random(secrets.randbits(128))
            grid = []
            for r in range(100):
                row = []
                for c in range(100):
                    if r < 50 and c < 50:
                        base = 3.0 + trial * 1.7
                    elif r >= 50 and c >= 50:
                        base = 8.5 - trial * 0.9
                    else:
                        base = -2.0 + trial
                    row.append(base + rng.uniform(-3.0, 3.0) + 0.002 * r - 0.001 * c)
                grid.append(row)
            with open(MESH_FILE, 'w', encoding='utf-8') as f:
                for row in grid:
                    f.write(','.join(format(x, '.17g') for x in row) + '\n')
            run_program()
            validate_output(expected_stats(grid))
    finally:
        with open(MESH_FILE, 'wb') as f:
            f.write(original_mesh)

    # Run the submitted Go program on the required original input.
    run_program()

    # Read the CSV and extract Q1 and Q4
    q1 = []
    q4 = []
    with open(MESH_FILE, 'r') as f:
        for row_idx, line in enumerate(f):
            if not line.strip():
                continue
            cols = [float(x) for x in line.strip().split(',')]
            if row_idx < 50:
                q1.extend(cols[:50])
            elif 50 <= row_idx < 100:
                q4.extend(cols[50:100])

    n1 = len(q1)
    n4 = len(q4)
    assert n1 == 2500, f'Expected 2500 elements in Q1, got {n1}'
    assert n4 == 2500, f'Expected 2500 elements in Q4, got {n4}'

    mean_q1 = sum(q1) / n1
    mean_q4 = sum(q4) / n4
    var_q1 = sum((x - mean_q1) ** 2 for x in q1) / (n1 - 1)
    var_q4 = sum((x - mean_q4) ** 2 for x in q4) / (n4 - 1)
    t_stat = (mean_q1 - mean_q4) / math.sqrt(var_q1 / n1 + var_q4 / n4)
    num = (var_q1 / n1 + var_q4 / n4) ** 2
    den = ((var_q1 / n1) ** 2) / (n1 - 1) + ((var_q4 / n4) ** 2) / (n4 - 1)
    df = num / den

    expected = {
        'mean_q1': mean_q1,
        'mean_q4': mean_q4,
        'var_q1': var_q1,
        'var_q4': var_q4,
        't_stat': t_stat,
        'df': df,
    }
    validate_output(expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
