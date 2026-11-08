#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess
import time
from pathlib import Path

import pytest

HOME = Path('/home/user')
ARTIFACTS = HOME / 'data/artifacts.csv'
WEIGHTS = HOME / 'data/weights.txt'
RESULTS = HOME / 'results.json'

ORIGINAL_ARTIFACTS = '''1,10,0.5,1.2,0.1
2,,0.1,NaN,0.9
3,1.5,0.1,0.2,0.3
NaN,5,0.1,0.2,0.3
5,2,1.0,1.0,1.0
6,0,0.0,0.0,0.0
7,-1,0.5,0.5,0.5
'''
ORIGINAL_WEIGHTS = '0.5,1.5,0.2,0.8\n'


def expected_values(csv_text, weights_text):
    weights = [float(w) for w in weights_text.strip().split(',')]
    assert len(weights) == 4
    valid_rows = 0
    inference_sum = 0.0

    for line in csv_text.splitlines():
        line = line.strip()
        if not line:
            continue
        cols = line.split(',')
        if len(cols) != 5:
            continue
        id_str, count_str, f1_str, f2_str, f3_str = cols

        try:
            int(id_str)
        except ValueError:
            continue

        if count_str == '' or count_str == 'NaN':
            count = 0
        elif '.' in count_str:
            continue
        else:
            try:
                count = int(count_str)
            except ValueError:
                continue

        def parse_float(value):
            if value == '' or value == 'NaN':
                return 0.0
            return float(value)

        try:
            f1 = parse_float(f1_str)
            f2 = parse_float(f2_str)
            f3 = parse_float(f3_str)
        except ValueError:
            continue

        valid_rows += 1
        inference_sum += (
            count * weights[0] + f1 * weights[1] +
            f2 * weights[2] + f3 * weights[3]
        )

    return valid_rows, inference_sum


def validate_results(expected_rows, expected_sum):
    assert RESULTS.is_file(), f'Expected output file {RESULTS} does not exist.'
    try:
        with RESULTS.open() as f:
            results = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'{RESULTS} is not valid JSON.')

    assert 'valid_rows' in results, "Missing 'valid_rows' in results.json"
    assert 'inference_sum' in results, "Missing 'inference_sum' in results.json"
    assert 'benchmark_time_ms' in results, "Missing 'benchmark_time_ms' in results.json"
    assert results['valid_rows'] == expected_rows, (
        f"Expected valid_rows to be {expected_rows}, got {results['valid_rows']}."
    )
    assert abs(results['inference_sum'] - expected_sum) < 1e-3, (
        f"Expected inference_sum approx {expected_sum:.4f}, got {results['inference_sum']}."
    )
    assert isinstance(results['benchmark_time_ms'], (int, float)), (
        'benchmark_time_ms must be a number.'
    )
    assert not isinstance(results['benchmark_time_ms'], bool)
    assert math.isfinite(results['benchmark_time_ms'])
    assert results['benchmark_time_ms'] > 0, 'benchmark_time_ms must be greater than 0.'
    return results


def source_candidates():
    extensions = {'.cpp', '.cc', '.cxx'}
    candidates = []
    for path in HOME.rglob('*'):
        if path.is_file() and path.suffix.lower() in extensions:
            try:
                text = path.read_text(errors='ignore')
            except OSError:
                continue
            if re.search(r'\bmain\s*\(', text):
                candidates.append((path, text))
    return candidates


def source_has_required_implementation(path):
    files = []
    for p in path.parent.iterdir():
        if p.is_file() and p.suffix.lower() in {'.cpp', '.cc', '.cxx', '.h', '.hh', '.hpp'}:
            files.append(p)
    combined = '\n'.join(p.read_text(errors='ignore') for p in files)
    compact = re.sub(r"[\s']+", '', combined).lower()

    assert re.search(r'eigen(?:3)?/', combined, re.IGNORECASE) or 'Eigen::' in combined, (
        'The submitted C++ program does not use Eigen.'
    )
    assert re.search(r'\b(for|while)\s*\(', combined), (
        'The submitted C++ program has no benchmark loop.'
    )
    assert ('10000' in compact or '10*1000' in compact or
            '100*100' in compact or '1e4' in compact), (
        'The submitted source does not specify 10,000 benchmark iterations.'
    )
    assert ('chrono' in combined.lower()), (
        'The submitted C++ program does not measure benchmark time.'
    )
    return files


def compile_candidate(main_path, related_files, number):
    build_dir = Path('/tmp/verifier_cpp_build')
    build_dir.mkdir(parents=True, exist_ok=True)
    executable = build_dir / f'candidate_{number}'

    sources = []
    for p in related_files:
        if p.suffix.lower() not in {'.cpp', '.cc', '.cxx'}:
            continue
        text = p.read_text(errors='ignore')
        if p == main_path or not re.search(r'\bmain\s*\(', text):
            sources.append(str(p))

    command = [
        'g++', '-std=c++17', '-O0', '-I/usr/include/eigen3',
        *sources, '-o', str(executable)
    ]
    completed = subprocess.run(
        command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=60
    )
    if completed.returncode != 0:
        raise AssertionError(
            f'Failed to compile {main_path}:\n{completed.stderr[-4000:]}'
        )
    assert executable.is_file() and os.access(executable, os.X_OK)
    return executable


def run_case(executable, csv_text, weights_text):
    ARTIFACTS.write_text(csv_text)
    WEIGHTS.write_text(weights_text)
    RESULTS.unlink(missing_ok=True)

    started = time.monotonic()
    completed = subprocess.run(
        [str(executable)], cwd=str(HOME), stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=120
    )
    wall_ms = (time.monotonic() - started) * 1000.0
    assert completed.returncode == 0, (
        f'Compiled program exited with {completed.returncode}:\n{completed.stderr[-4000:]}'
    )

    expected_rows, expected_sum = expected_values(csv_text, weights_text)
    results = validate_results(expected_rows, expected_sum)
    assert results['benchmark_time_ms'] <= wall_ms + 100.0, (
        'Reported benchmark time exceeds the total program runtime.'
    )
    return results


def test_results_json_and_cpp_execution():
    assert ARTIFACTS.is_file(), f'Missing {ARTIFACTS} to compute truth.'
    assert WEIGHTS.is_file(), f'Missing {WEIGHTS} to compute truth.'

    candidates = source_candidates()
    assert candidates, 'No C++ source file containing main() was found under /home/user.'

    # A substantially larger independently generated fixture makes a real 10,000-iteration
    # matrix benchmark measurably scale while also preventing hard-coded result files.
    dynamic_lines = []
    for i in range(1, 513):
        count = (i % 17) - 8
        f1 = (i % 11) / 8.0
        f2 = 'NaN' if i % 19 == 0 else str((i % 13) / 7.0)
        f3 = '' if i % 23 == 0 else str(-((i % 9) / 6.0))
        dynamic_lines.append(f'{1000 + i},{count},{f1},{f2},{f3}')
    dynamic_lines += [
        'NaN,4,1,2,3',
        '9999,4.0,1,2,3',
        '10000,not_an_int,1,2,3',
        '10001,2,not_a_float,2,3',
    ]
    dynamic_csv = '\n'.join(dynamic_lines) + '\n'
    dynamic_weights = '-1.25,0.75,2.5,-0.5\n'

    failures = []
    successful_executable = None
    try:
        for number, (main_path, _) in enumerate(candidates):
            try:
                related = source_has_required_implementation(main_path)
                executable = compile_candidate(main_path, related, number)

                original_result = run_case(
                    executable, ORIGINAL_ARTIFACTS, ORIGINAL_WEIGHTS
                )
                dynamic_result = run_case(
                    executable, dynamic_csv, dynamic_weights
                )
                assert dynamic_result['benchmark_time_ms'] > original_result['benchmark_time_ms'] * 1.5, (
                    'Benchmark time did not scale for a much larger matrix; the required '
                    '10,000 Eigen matrix multiplications do not appear to have been benchmarked.'
                )
                successful_executable = executable
                break
            except Exception as exc:
                failures.append(f'{main_path}: {exc}')

        assert successful_executable is not None, (
            'No submitted C++ program compiled and passed execution tests:\n' +
            '\n'.join(failures[-10:])
        )
    finally:
        ARTIFACTS.write_text(ORIGINAL_ARTIFACTS)
        WEIGHTS.write_text(ORIGINAL_WEIGHTS)

    # Leave results.json generated by the freshly compiled program for the original fixture.
    run_case(successful_executable, ORIGINAL_ARTIFACTS, ORIGINAL_WEIGHTS)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
