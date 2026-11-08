#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess

import pytest
import requests

BINARY_PATH = '/app/ridge_solver/solver'
SOURCE_PATH = '/app/ridge_solver/src/solver.cpp'
URL = 'http://127.0.0.1:8080/fit'


def expected_ridge(points, lam):
    sum_x2 = sum(x * x for x, _ in points)
    sum_x = sum(x for x, _ in points)
    sum_y = sum(y for _, y in points)
    sum_xy = sum(x * y for x, y in points)
    a = sum_x2 + lam
    b = sum_x
    c = sum_x
    d = len(points) + lam
    det = a * d - b * c
    return ((d * sum_xy - b * sum_y) / det,
            (-c * sum_xy + a * sum_y) / det)


def assert_weights(actual_w1, actual_w0, expected_w1, expected_w0):
    assert math.isfinite(actual_w1), f'w1 is not finite: {actual_w1}'
    assert math.isfinite(actual_w0), f'w0 is not finite: {actual_w0}'
    assert math.isclose(actual_w1, expected_w1, rel_tol=2e-4, abs_tol=2e-5), \
        f'Expected w1 approximately {expected_w1}, got {actual_w1}'
    assert math.isclose(actual_w0, expected_w0, rel_tol=2e-4, abs_tol=2e-5), \
        f'Expected w0 approximately {expected_w0}, got {actual_w0}'


def run_solver(binary, points, lam, csv_path):
    with open(csv_path, 'w') as f:
        for x, y in points:
            f.write(f'{x!r},{y!r}\n')

    result = subprocess.run(
        [binary, str(lam), str(csv_path)],
        cwd='/app/ridge_solver', capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, \
        f'Solver failed with code {result.returncode}: {result.stderr}'
    lines = result.stdout.strip().splitlines()
    assert len(lines) == 1, f'Expected one output line, got: {result.stdout!r}'
    parts = lines[0].split(',')
    assert len(parts) == 2 and parts[0].startswith('w1=') and parts[1].startswith('w0='), \
        f'Unexpected solver output: {result.stdout!r}'
    return float(parts[0].split('=', 1)[1]), float(parts[1].split('=', 1)[1])


def generated_cases():
    rng = random.SystemRandom()

    # A truly singular unregularized design (all x values identical).
    base = rng.uniform(-4.0, 4.0)
    constant_points = [(base, rng.uniform(-8.0, 8.0)) for _ in range(5)]

    # A near-singular design with unpredictable values.
    near_base = rng.uniform(-3.0, 3.0)
    near_points = [
        (near_base + (i - 3) * 1e-9, rng.uniform(-6.0, 6.0))
        for i in range(7)
    ]

    # A normal full-rank design with another regularization strength.
    general_points = [
        (rng.uniform(-5.0, 5.0), rng.uniform(-10.0, 10.0))
        for _ in range(9)
    ]

    return [
        (constant_points, rng.uniform(0.15, 1.7)),
        (near_points, rng.uniform(0.03, 0.4)),
        (general_points, rng.uniform(1.8, 4.0)),
    ]


CASES = generated_cases()


def test_solver_binary_exists_and_linked_openmp():
    assert os.path.isfile(BINARY_PATH), \
        "The compiled binary 'solver' is missing in /app/ridge_solver"
    assert os.access(BINARY_PATH, os.X_OK), f'The file {BINARY_PATH} is not executable'

    try:
        ldd_output = subprocess.check_output(['ldd', BINARY_PATH], text=True)
        assert 'libgomp' in ldd_output or 'libomp' in ldd_output, \
            'The binary does not appear to be linked with OpenMP (e.g. libgomp). Did you compile with OpenMP support?'
    except subprocess.CalledProcessError:
        pytest.fail('Failed to run ldd on the compiled binary to check for OpenMP linkage.')


def test_service_responses():
    # Preserve the original singular-input regression check.
    payload = {
        'lambda': 1.0,
        'points': [
            {'x': 1.0, 'y': 2.0},
            {'x': 1.0, 'y': 2.0}
        ]
    }

    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail('Failed to connect to the server at 127.0.0.1:8080. Is the server running?')
    except requests.exceptions.Timeout:
        pytest.fail('Request to the server timed out.')

    assert response.status_code == 200, \
        f'Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}'

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f'Expected JSON response, got: {response.text}')

    assert 'w1' in data and 'w0' in data, \
        f"Response JSON missing 'w1' or 'w0' keys: {data}"
    assert not math.isnan(data['w1']), \
        'w1 is NaN. The regularization parameter lambda was not correctly applied to prevent division by zero.'
    assert not math.isnan(data['w0']), \
        'w0 is NaN. The regularization parameter lambda was not correctly applied to prevent division by zero.'
    assert math.isclose(data['w1'], 0.8, rel_tol=1e-4), \
        f"Expected w1 approximately 0.8, got {data['w1']}. Ensure lambda is added to both a and d."
    assert math.isclose(data['w0'], 0.8, rel_tol=1e-4), \
        f"Expected w0 approximately 0.8, got {data['w0']}. Ensure lambda is added to both a and d."


def test_submitted_binary_and_source_on_unpredictable_inputs(tmp_path):
    assert os.path.isfile(SOURCE_PATH), f'Missing required source file: {SOURCE_PATH}'
    rebuilt = tmp_path / 'solver_from_submitted_source'
    compile_result = subprocess.run(
        ['g++', '-O2', '-fopenmp', SOURCE_PATH, '-o', str(rebuilt)],
        capture_output=True, text=True, timeout=30
    )
    assert compile_result.returncode == 0, \
        f'The submitted solver.cpp does not compile with OpenMP: {compile_result.stderr}'

    for case_index, (points, lam) in enumerate(CASES):
        expected_w1, expected_w0 = expected_ridge(points, lam)
        for binary_index, binary in enumerate((BINARY_PATH, str(rebuilt))):
            csv_path = tmp_path / f'case_{case_index}_{binary_index}.csv'
            actual_w1, actual_w0 = run_solver(binary, points, lam, csv_path)
            assert_weights(actual_w1, actual_w0, expected_w1, expected_w0)


def test_service_on_unpredictable_inputs():
    for points, lam in CASES:
        payload = {
            'lambda': lam,
            'points': [{'x': x, 'y': y} for x, y in points]
        }
        try:
            response = requests.post(URL, json=payload, timeout=5)
        except requests.exceptions.RequestException as exc:
            pytest.fail(f'Failed to call the running service: {exc}')

        assert response.status_code == 200, \
            f'Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}'
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f'Expected JSON response, got: {response.text}')
        assert 'w1' in data and 'w0' in data, \
            f"Response JSON missing 'w1' or 'w0' keys: {data}"

        expected_w1, expected_w0 = expected_ridge(points, lam)
        assert_weights(data['w1'], data['w0'], expected_w1, expected_w0)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
