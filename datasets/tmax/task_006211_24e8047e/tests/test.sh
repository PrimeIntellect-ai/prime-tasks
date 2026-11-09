#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import random
import re
import shlex
import subprocess
import sys

import pytest

DATA_DIR = '/home/user/telemetry_data'
OUTPUT = '/home/user/telemetry_summary.csv'
EXPECTED_HEADER = ['server_id', 'node_id', 'metric', 'average_value']


def telemetry_paths():
    return [os.path.join(DATA_DIR, f'telemetry_{i:02d}.csv') for i in range(1, 51)]


def compute_expected_results():
    expected_sums = {}
    expected_counts = {}

    for filepath in telemetry_paths():
        assert os.path.exists(filepath), f'Mandatory input file is missing: {filepath}'
        assert os.path.isfile(filepath), f'Mandatory input path is not a file: {filepath}'

        with open(filepath, 'r', newline='') as f:
            reader = csv.reader(f)
            rows = list(reader)

        assert rows, f'Mandatory input file is empty: {filepath}'
        data_rows = rows[1:]

        # Remove exact duplicate rows within each file.
        seen = set()
        unique_rows = []
        for row in data_rows:
            row_tuple = tuple(row)
            if row_tuple not in seen:
                seen.add(row_tuple)
                unique_rows.append(row)

        for row in unique_rows:
            if len(row) != 6:
                continue

            ts, srv, c1, m1, c2, m2 = row
            srv = srv.strip().upper()

            def is_missing(v):
                return v == '' or v == 'NaN'

            if is_missing(c1) and is_missing(m1) and is_missing(c2) and is_missing(m2):
                continue

            def get_val(v):
                return 0.0 if is_missing(v) else float(v)

            metrics = [
                ('node1', 'cpu', get_val(c1)),
                ('node1', 'mem', get_val(m1)),
                ('node2', 'cpu', get_val(c2)),
                ('node2', 'mem', get_val(m2)),
            ]

            for node_id, metric, val in metrics:
                key = (srv, node_id, metric)
                expected_sums[key] = expected_sums.get(key, 0.0) + val
                expected_counts[key] = expected_counts.get(key, 0) + 1

    expected_results = []
    for key in expected_sums:
        avg = round(expected_sums[key] / expected_counts[key], 2)
        expected_results.append((*key, f'{avg:.2f}'))

    expected_results.sort()
    return expected_results


def write_controlled_inputs():
    os.makedirs(DATA_DIR, exist_ok=True)
    rng = random.SystemRandom()
    nonce = rng.randrange(10_000_000, 99_999_999)

    for i, filepath in enumerate(telemetry_paths(), 1):
        base = rng.randrange(10, 500) * 2
        server = f'check-{nonce}-{i:02d}'
        row1 = [
            f'2026-01-{(i % 28) + 1:02d}T00:00:00',
            f'  {server.lower()} ',
            str(base), '', str(base + 2), 'NaN'
        ]
        row2 = [
            f'2026-01-{(i % 28) + 1:02d}T00:01:00',
            server.upper(),
            str(base + 2), str(base * 2), '', str(base * 2 + 2)
        ]
        all_missing = [
            f'2026-01-{(i % 28) + 1:02d}T00:02:00',
            server,
            '', 'NaN', '', ''
        ]
        with open(filepath, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['timestamp', 'server_id', 'cpu_node1', 'mem_node1', 'cpu_node2', 'mem_node2'])
            writer.writerow(row1)
            writer.writerow(row1)  # exact duplicate within this file
            writer.writerow(row2)
            writer.writerow(all_missing)


def has_parallel_implementation(path, text):
    lower = text.lower()
    try:
        tree = ast.parse(text, filename=path)
    except (SyntaxError, ValueError):
        tree = None

    if tree is not None:
        imported = set()
        calls = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imported.update(alias.name.split('.')[0] for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                imported.add(node.module.split('.')[0])
            elif isinstance(node, ast.Call):
                func = node.func
                if isinstance(func, ast.Name):
                    calls.add(func.id.lower())
                elif isinstance(func, ast.Attribute):
                    calls.add(func.attr.lower())

        APIs = {
            'pool', 'process', 'thread', 'processpoolexecutor',
            'threadpoolexecutor', 'parallel', 'delayed', 'compute',
            'popen', 'map_async', 'starmap', 'starmap_async'
        }
        if imported.intersection({'multiprocessing', 'concurrent', 'threading', 'dask', 'joblib', 'subprocess'}) and calls.intersection(APIs):
            return True
        if 'dask' in imported and calls.intersection({'read_csv', 'map_partitions', 'persist'}):
            return True

    non_python_patterns = [
        r'\bxargs\b[^\n]*\s-P\s*\d+',
        r'(?:^|[;\n])\s*parallel\s+',
        r'[^&]&\s*(?:\n|$)',
        r'worker_threads|promise\.all',
        r'\bgo\s+\w+\s*\(',
        r'waitgroup|executorservice|forkjoinpool',
        r'\.par_iter\s*\(|rayon',
        r'#\s*pragma\s+omp\s+parallel'
    ]
    return any(re.search(pattern, lower, re.MULTILINE) for pattern in non_python_patterns)


def find_processing_scripts():
    candidates = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if os.path.join(root, d) != DATA_DIR and d not in {'.cache', '.git', '__pycache__'}]
        if root.startswith(DATA_DIR):
            continue
        for name in files:
            path = os.path.join(root, name)
            if path == OUTPUT or name.lower().endswith('.csv') or os.path.islink(path):
                continue
            try:
                if os.path.getsize(path) > 2_000_000:
                    continue
                with open(path, 'r', encoding='utf-8') as f:
                    text = f.read()
            except (OSError, UnicodeError):
                continue
            lower = text.lower()
            if 'telemetry_data' not in lower or 'telemetry_summary.csv' not in lower:
                continue
            if has_parallel_implementation(path, text):
                candidates.append((path, text))
    return sorted(candidates)


def command_for(path, text):
    suffix = os.path.splitext(path)[1].lower()
    first = text.splitlines()[0] if text.splitlines() else ''
    if suffix == '.py' or (first.startswith('#!') and 'python' in first.lower()):
        return [sys.executable, path]
    if suffix in {'.sh', '.bash'} or (first.startswith('#!') and ('/sh' in first or 'bash' in first)):
        return ['bash', path]
    if suffix == '.pl':
        return ['perl', path]
    if suffix == '.rb':
        return ['ruby', path]
    if suffix == '.js':
        return ['node', path]
    if os.access(path, os.X_OK):
        return [path]
    if first.startswith('#!'):
        return shlex.split(first[2:].strip()) + [path]
    return None


def output_matches_expected():
    if not os.path.isfile(OUTPUT):
        return False
    try:
        with open(OUTPUT, 'r', newline='') as f:
            rows = list(csv.reader(f))
        if not rows or rows[0] != EXPECTED_HEADER:
            return False
        expected = compute_expected_results()
        actual = rows[1:]
        if len(actual) != len(expected):
            return False
        for row, expected_row in zip(actual, expected):
            if len(row) != 4:
                return False
            formatted = (row[0], row[1], row[2], f'{float(row[3]):.2f}')
            if formatted != expected_row:
                return False
        return True
    except (OSError, ValueError, IndexError):
        return False


def test_mandatory_input_files_were_not_removed():
    for path in telemetry_paths():
        assert os.path.exists(path), f'Mandatory telemetry input was removed: {path}'
        assert os.path.isfile(path), f'Mandatory telemetry input is not a regular file: {path}'
        assert not os.path.islink(path), f'Mandatory telemetry input was replaced by a symlink: {path}'


def test_parallel_processing_script_executes():
    candidates = find_processing_scripts()
    assert candidates, 'No processing script with a parallel-processing implementation was found.'

    failures = []
    for path, text in candidates:
        command = command_for(path, text)
        if command is None:
            failures.append(f'{path}: cannot execute this script')
            continue

        write_controlled_inputs()
        try:
            if os.path.lexists(OUTPUT):
                os.remove(OUTPUT)
            result = subprocess.run(
                command,
                cwd='/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=120,
                env={**os.environ, 'HOME': '/home/user'}
            )
        except Exception as exc:
            failures.append(f'{path}: {exc}')
            continue

        if result.returncode != 0:
            failures.append(f'{path}: exited {result.returncode}: {result.stderr[-500:]}')
            continue
        if output_matches_expected():
            return
        failures.append(f'{path}: output did not match the controlled telemetry inputs')

    pytest.fail('No parallel processing script successfully generated the required output. ' + ' | '.join(failures))


def test_summary_file_exists():
    assert os.path.exists(OUTPUT), 'The output file /home/user/telemetry_summary.csv does not exist.'
    assert os.path.isfile(OUTPUT), '/home/user/telemetry_summary.csv is not a file.'


def test_summary_file_content():
    with open(OUTPUT, 'r', newline='') as f:
        rows = list(csv.reader(f))

    assert len(rows) > 0, 'The output file is empty.'
    header = rows[0]
    assert header == EXPECTED_HEADER, f'Incorrect header. Expected {EXPECTED_HEADER}, but got {header}.'

    actual_data = rows[1:]
    expected_data = compute_expected_results()
    assert len(actual_data) == len(expected_data), f'Expected {len(expected_data)} rows, but got {len(actual_data)} rows.'

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert len(actual) == 4, f'Row {i+1} has {len(actual)} columns instead of 4.'
        try:
            actual_avg = f'{float(actual[3]):.2f}'
            actual_formatted = (actual[0], actual[1], actual[2], actual_avg)
        except ValueError:
            actual_formatted = tuple(actual)
        assert actual_formatted == expected, f'Row {i+1} mismatch. Expected {expected}, got {actual_formatted}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
