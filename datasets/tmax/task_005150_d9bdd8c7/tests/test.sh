#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import resource
import subprocess
import time

import pytest

CPP_PATH = '/home/user/tune_and_benchmark.cpp'
BINARY_PATH = '/tmp/tune_and_benchmark_verifier'


def load_rows(csv_path):
    rows = []
    with open(csv_path, 'r') as f:
        lines = f.read().strip().split('\n')
    for line in lines[1:]:
        if not line.strip():
            continue
        parts = line.split(',')
        rows.append({
            'id': int(parts[0]),
            'fold': int(parts[1]),
            'x': float(parts[2]),
            'y': float(parts[3]),
        })
    return rows


def expected_result(rows):
    def knn_predict(train_data, test_x, k):
        distances = []
        for row in train_data:
            dist = abs(row['x'] - test_x)
            distances.append((dist, row['id'], row['y']))
        distances.sort(key=lambda item: (item[0], item[1]))
        top_k = distances[:k]
        return sum(item[2] for item in top_k) / k

    mses_by_k = {}
    for k in [1, 3, 5, 7, 9]:
        fold_mses = []
        for fold in [1, 2, 3]:
            train = [r for r in rows if r['fold'] != fold]
            test = [r for r in rows if r['fold'] == fold]
            sq_errors = []
            for row in test:
                pred = knn_predict(train, row['x'], k)
                sq_errors.append((row['y'] - pred) ** 2)
            fold_mses.append(sum(sq_errors) / len(sq_errors))
        mses_by_k[k] = sum(fold_mses) / len(fold_mses)

    best_k = min(mses_by_k.keys(), key=lambda k: (mses_by_k[k], k))
    return best_k, mses_by_k[best_k]


def validate_values(report, rows):
    best_k, best_mse = expected_result(rows)
    assert report['best_k'] == best_k, \
        f"Expected best_k to be {best_k}, got {report['best_k']}."

    expected_mse_rounded = round(best_mse, 4)
    reported_mse = report['best_cv_mse']
    assert isinstance(reported_mse, (int, float)) and not isinstance(reported_mse, bool)
    assert math.isfinite(reported_mse)
    assert abs(reported_mse - expected_mse_rounded) < 1e-4 or abs(reported_mse - best_mse) < 1e-4, \
        f"Expected best_cv_mse to be close to {expected_mse_rounded}, got {reported_mse}."

    benchmark_time = report['benchmark_time_microseconds']
    assert isinstance(benchmark_time, int) and not isinstance(benchmark_time, bool), \
        'benchmark_time_microseconds should be an integer.'
    assert benchmark_time > 0, 'benchmark_time_microseconds should be greater than 0.'


def execute_program(csv_path, output_path):
    if os.path.exists(output_path):
        os.unlink(output_path)

    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    started = time.monotonic_ns()
    result = subprocess.run(
        [BINARY_PATH, csv_path, output_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    elapsed_us = (time.monotonic_ns() - started) / 1000.0
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    child_cpu_us = (
        (after.ru_utime - before.ru_utime) +
        (after.ru_stime - before.ru_stime)
    ) * 1_000_000.0

    assert result.returncode == 0, \
        f'Compiled program failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    assert os.path.isfile(output_path), 'Program did not create the requested output JSON file.'
    with open(output_path, 'r') as f:
        report = json.load(f)

    benchmark = report.get('benchmark_time_microseconds')
    assert isinstance(benchmark, int) and not isinstance(benchmark, bool)
    assert benchmark > 0
    # An internally measured benchmark must fit within the externally observed run,
    # and the required 1000 prediction passes should represent nontrivial child CPU work.
    assert benchmark <= elapsed_us + 5000, \
        'Reported benchmark time exceeds the complete externally measured execution time.'
    assert benchmark >= max(100, child_cpu_us * 0.05), \
        'Reported benchmark time is not consistent with actually running the required benchmark.'
    return report


@pytest.fixture(scope='session')
def compiled_program():
    assert os.path.isfile(CPP_PATH), f'C++ source file {CPP_PATH} is missing.'
    result = subprocess.run(
        ['g++', '-O3', '-std=c++17', CPP_PATH, '-o', BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, \
        f'C++ source did not compile:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK)
    return BINARY_PATH


def test_cpp_file_exists():
    """Verify that the C++ source file was created at the correct path."""
    assert os.path.isfile(CPP_PATH), f'C++ source file {CPP_PATH} is missing.'


def test_report_exists_and_format():
    """Verify that the report.json exists and has the required keys."""
    report_path = '/home/user/report.json'
    assert os.path.isfile(report_path), f'Report file {report_path} is missing.'

    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'Report file {report_path} is not valid JSON.')

    assert 'best_k' in data, "Missing 'best_k' in report.json."
    assert 'best_cv_mse' in data, "Missing 'best_cv_mse' in report.json."
    assert 'benchmark_time_microseconds' in data, "Missing 'benchmark_time_microseconds' in report.json."


def test_report_values():
    """Recompute the ground truth for KNN CV MSE and verify the report's values."""
    csv_path = '/home/user/spectra.csv'
    assert os.path.isfile(csv_path), f'Dataset file {csv_path} is missing.'
    rows = load_rows(csv_path)
    with open('/home/user/report.json', 'r') as f:
        report = json.load(f)
    validate_values(report, rows)


def test_compiled_program_on_supplied_dataset(compiled_program):
    report = execute_program('/home/user/spectra.csv', '/tmp/verifier_original_report.json')
    validate_values(report, load_rows('/home/user/spectra.csv'))


def test_compiled_program_on_independent_dataset(compiled_program):
    csv_path = '/tmp/verifier_spectra.csv'
    with open(csv_path, 'w') as f:
        f.write('id,fold,x,y\n')
        for i in range(60):
            fold = (i % 3) + 1
            x = ((i * 17) % 47) / 4.0
            y = 1.75 * x * x - 2.5 * x + ((i * 11) % 9 - 4) * 0.13
            f.write(f'{1000 + i},{fold},{x:.6f},{y:.6f}\n')

    output_path = '/tmp/verifier_independent_report.json'
    report = execute_program(csv_path, output_path)
    validate_values(report, load_rows(csv_path))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
