#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

import cv2
import requests

STATE = '/home/user/initial_state.txt'
SOURCE = '/home/user/simulate.c'
BINARY = '/tmp/verified_simulate'
URL = 'http://127.0.0.1:8080/simulate'
NUMBER = re.compile(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$')


def read_state(path):
    with open(path, 'r') as f:
        lines = f.readlines()
    assert len(lines) == 64, f'Expected 64 lines in {path}, got {len(lines)}'
    matrix = []
    for i, line in enumerate(lines):
        parts = line.strip().split()
        assert len(parts) == 64, f'Expected 64 values on line {i+1}, got {len(parts)}'
        row = [float(x) for x in parts]
        assert all(math.isfinite(x) and 0.0 <= x <= 1.0 for x in row), \
            f'Invalid normalized pixel value on line {i+1}'
        matrix.append(row)
    return matrix


def run_binary(t_end, timeout=20):
    result = subprocess.run(
        [BINARY, str(t_end)], text=True, capture_output=True, timeout=timeout
    )
    assert result.returncode == 0, \
        f'simulate.c executable failed for T={t_end}: {result.stderr}'
    text = result.stdout.strip()
    assert NUMBER.fullmatch(text), \
        f'Expected exactly one floating-point value on stdout, got {result.stdout!r}'
    value = float(text)
    assert math.isfinite(value), f'Simulation produced a non-finite result for T={t_end}'
    return value


def call_service(t_end, timeout=15):
    try:
        response = requests.post(URL, json={'t_end': t_end}, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        assert False, f'Failed to connect to the HTTP service at {URL}: {exc}'
    assert response.status_code == 200, \
        f'Expected status code 200, got {response.status_code}. Response: {response.text}'
    try:
        data = response.json()
    except ValueError:
        assert False, f'Response is not valid JSON: {response.text}'
    assert 'sum' in data, f"Response JSON missing 'sum' key: {data}"
    value = float(data['sum'])
    assert math.isfinite(value), f'Service returned a non-finite sum: {data}'
    return value


def write_state(matrix):
    with open(STATE, 'w') as f:
        for row in matrix:
            f.write(' '.join(format(x, '.9g') for x in row) + '\n')


def test_initial_state_file():
    assert os.path.isfile(STATE), f'File {STATE} does not exist.'
    actual = read_state(STATE)

    cap = cv2.VideoCapture('/app/diffusion.mp4')
    ok, frame = cap.read()
    cap.release()
    assert ok and frame is not None, 'Could not decode the first video frame'
    assert frame.shape[:2] == (64, 64), f'Unexpected first-frame shape: {frame.shape}'
    expected = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY).astype('float64') / 255.0

    # Allow minor differences between standard grayscale conversion formulas, but
    # require every entry to come from the decoded first frame.
    tolerance = 2.1 / 255.0
    for i in range(64):
        for j in range(64):
            assert abs(actual[i][j] - float(expected[i, j])) <= tolerance, \
                f'Pixel ({i},{j}) differs from the decoded first frame: ' \
                f'{actual[i][j]} vs {expected[i, j]}'

    total_sum = sum(map(sum, actual))
    assert math.isclose(total_sum, 100.0, rel_tol=0.05), \
        f'Expected initial sum to be around 100.0, got {total_sum}'


def test_simulate_c_exists_and_executes():
    assert os.path.isfile(SOURCE), f'File {SOURCE} does not exist.'
    result = subprocess.run(
        ['gcc', '-O2', '-std=c11', '-Wall', '-Wextra', SOURCE, '-lm', '-o', BINARY],
        text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, f'simulate.c did not compile:\n{result.stderr}'
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)

    initial_sum = sum(map(sum, read_state(STATE)))
    for t_end in (0.0, 0.37, 10.0, 50.0, 250.0):
        value = run_binary(t_end)
        assert math.isclose(value, initial_sum, rel_tol=1e-3, abs_tol=2e-2), \
            f'Periodic heat simulation failed to conserve the sum at T={t_end}: {value}'


def test_http_service():
    sim_sum = call_service(10.0, timeout=5)
    assert math.isclose(sim_sum, 100.0, rel_tol=0.05), \
        f'Expected sum to be conserved around 100.0, got {sim_sum}'


def test_http_service_different_time():
    sim_sum = call_service(50.0, timeout=10)
    assert math.isclose(sim_sum, 100.0, rel_tol=0.05), \
        f'Expected sum to be conserved around 100.0 even for larger t_end, got {sim_sum}'


def test_c_and_service_use_supplied_state_on_derived_cases():
    # Secret, verifier-generated states prevent a fixed 100.0 response from passing.
    with open(STATE, 'rb') as f:
        original = f.read()
    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    cases = []
    cases.append(([[0.013 + 0.00007 * ((i * 64 + j) % 97) for j in range(64)]
                   for i in range(64)], 1.13))
    cases.append(([[rng.uniform(0.15, 0.85) if (i + j) % 2 else rng.uniform(0.0, 0.2)
                    for j in range(64)] for i in range(64)], 123.45))

    try:
        for matrix, t_end in cases:
            write_state(matrix)
            # Derive the expected answer from the exact decimal values supplied.
            supplied = read_state(STATE)
            expected_sum = sum(map(sum, supplied))

            direct = run_binary(t_end)
            assert math.isclose(direct, expected_sum, rel_tol=1e-3, abs_tol=2e-2), \
                f'Compiled C simulation gave {direct}; expected conserved sum {expected_sum}'

            served = call_service(t_end)
            assert math.isclose(served, direct, rel_tol=1e-3, abs_tol=2e-2), \
                f'Service result {served} does not match compiled C result {direct}'
            assert math.isclose(served, expected_sum, rel_tol=1e-3, abs_tol=2e-2), \
                f'Service did not process the supplied initial state: {served} vs {expected_sum}'
    finally:
        with open(STATE, 'wb') as f:
            f.write(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
