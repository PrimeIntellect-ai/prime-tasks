#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import shutil
import subprocess
import pytest

SOURCE_PATH = '/home/user/analyze.cpp'
BINARY_PATH = '/home/user/analyze'
METRICS_PATH = '/home/user/metrics.csv'
ALERTS_PATH = '/home/user/alerts.log'


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.remove(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def run_program():
    remove_path(ALERTS_PATH)
    result = subprocess.run(
        [BINARY_PATH],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f'Compiled program exited with status {result.returncode}. '
        f'stdout: {result.stdout!r}, stderr: {result.stderr!r}'
    )
    assert os.path.exists(ALERTS_PATH), (
        f'Program did not create {ALERTS_PATH}.'
    )
    assert os.path.isfile(ALERTS_PATH), f'{ALERTS_PATH} is not a file.'


def derive_expected(metrics_path):
    web01_rows = []
    with open(metrics_path, 'r', newline='') as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            if row[0] == 'web-01':
                web01_rows.append(row)

    sampled_rows = web01_rows[::5]
    expected_alerts = []
    for i in range(1, len(sampled_rows)):
        prev_val = int(sampled_rows[i - 1][2])
        curr_val = int(sampled_rows[i][2])
        delta = curr_val - prev_val
        if delta > 100:
            timestamp = sampled_rows[i][1]
            expected_alerts.append(
                f'[ALERT] web-01 spike at {timestamp}: +{delta}ms'
            )
    return expected_alerts


def read_alerts():
    with open(ALERTS_PATH, 'r') as f:
        return [line.strip() for line in f.readlines() if line.strip()]


@pytest.fixture(scope='session')
def compiled_program():
    assert os.path.exists(SOURCE_PATH), (
        f'Source file {SOURCE_PATH} is missing. Did you create it?'
    )
    assert os.path.isfile(SOURCE_PATH), f'{SOURCE_PATH} is not a file.'

    remove_path(BINARY_PATH)
    result = subprocess.run(
        ['g++', '-std=c++17', SOURCE_PATH, '-o', BINARY_PATH],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'{SOURCE_PATH} failed to compile with g++ -std=c++17. '
        f'stdout: {result.stdout!r}, stderr: {result.stderr!r}'
    )
    assert os.path.isfile(BINARY_PATH), f'Compiler did not create {BINARY_PATH}.'
    run_program()
    return BINARY_PATH


def test_analyze_cpp_exists():
    """Test that the C++ source file was created."""
    assert os.path.exists(SOURCE_PATH), (
        f'Source file {SOURCE_PATH} is missing. Did you create it?'
    )
    assert os.path.isfile(SOURCE_PATH), f'{SOURCE_PATH} is not a file.'


def test_program_compiles_and_runs(compiled_program):
    assert os.path.isfile(compiled_program)
    assert os.path.isfile(ALERTS_PATH)


def test_alerts_log_correctness(compiled_program):
    """Test that alerts.log contains alerts derived from the supplied CSV."""
    assert os.path.exists(ALERTS_PATH), (
        f'Output file {ALERTS_PATH} is missing. Did you run the program?'
    )
    assert os.path.exists(METRICS_PATH), f'Input file {METRICS_PATH} is missing.'

    expected_alerts_clean = derive_expected(METRICS_PATH)
    actual_alerts_clean = read_alerts()
    assert actual_alerts_clean == expected_alerts_clean, (
        f'Contents of {ALERTS_PATH} do not match the expected alerts. '
        f'Expected: {expected_alerts_clean}, Got: {actual_alerts_clean}'
    )


def test_pipeline_on_derived_input(compiled_program):
    """Execute the submitted program on an independent CSV test case."""
    with open(METRICS_PATH, 'rb') as f:
        original_metrics = f.read()

    values = [50, 900, 800, 700, 600, 151, 500, 450,
              350, 300, 251, 100, 90, 80, 70, 400]
    rows = [['server_id', 'timestamp', 'response_time']]
    for i, value in enumerate(values):
        rows.append(['web-02', f'noise-{i}', str(10000 + i)])
        rows.append(['web-010', f'near-match-{i}', str(20000 + i)])
        rows.append(['web-01', f'sample-{i}', str(value)])

    try:
        with open(METRICS_PATH, 'w', newline='') as f:
            csv.writer(f).writerows(rows)

        expected = derive_expected(METRICS_PATH)
        run_program()
        actual = read_alerts()
        assert actual == expected, (
            'Program failed on an independently generated input. '
            f'Expected: {expected}, Got: {actual}'
        )
    finally:
        with open(METRICS_PATH, 'wb') as f:
            f.write(original_metrics)
        run_program()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
