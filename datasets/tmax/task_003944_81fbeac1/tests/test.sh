#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import random
import re
import subprocess
import pytest

C_FILE = '/home/user/generate_labels.c'
RAW_FILE = '/home/user/raw_observations.csv'
CSV_FILE = '/home/user/training_data.csv'
EXECUTABLE = '/tmp/generate_labels_verifier'

EXPECTED_INPUTS = [
    (1, 0.5, 1.0),
    (2, 0.1, 2.0),
    (3, 0.8, 0.5),
    (4, 0.9, 3.1),
    (5, 0.25, 1.5),
]


def solve_kepler(a, b, tol=1e-6):
    x = b
    for _ in range(10000):
        f_x = x - a * math.sin(x) - b
        if abs(f_x) < tol:
            return x
        f_prime_x = 1 - a * math.cos(x)
        x = x - f_x / f_prime_x
    raise AssertionError(f'Newton-Raphson reference solver did not converge for a={a}, b={b}')


def write_input(rows):
    with open(RAW_FILE, 'w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['id', 'a', 'b'])
        writer.writerows(rows)


def run_program():
    if os.path.exists(CSV_FILE):
        os.remove(CSV_FILE)
    result = subprocess.run(
        [EXECUTABLE],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f'Compiled program exited with status {result.returncode}. '
        f'stdout: {result.stdout!r}; stderr: {result.stderr!r}'
    )


def read_and_check_rows(expected_inputs):
    assert os.path.exists(CSV_FILE), f'Expected output file at {CSV_FILE} is missing.'
    assert os.path.isfile(CSV_FILE), f'Path {CSV_FILE} is not a file.'

    with open(CSV_FILE, 'r', newline='') as f:
        reader = list(csv.reader(f))

    assert len(reader) == len(expected_inputs), (
        f'Expected {len(expected_inputs)} rows in {CSV_FILE}, but found {len(reader)}.'
    )

    for i, row in enumerate(reader):
        assert len(row) == 4, f'Row {i+1} does not have exactly 4 columns: {row}'
        try:
            r_id = int(row[0])
            r_a = float(row[1])
            r_b = float(row[2])
            float(row[3])
        except ValueError:
            assert False, f'Row {i+1} contains non-numeric data: {row}'

        exp_id, exp_a, exp_b = expected_inputs[i]
        assert r_id == exp_id, f'Row {i+1} ID mismatch. Expected {exp_id}, got {r_id}'
        assert abs(r_a - exp_a) < 1e-9, (
            f"Row {i+1} 'a' mismatch. Expected {exp_a}, got {r_a}"
        )
        assert abs(r_b - exp_b) < 1e-9, (
            f"Row {i+1} 'b' mismatch. Expected {exp_b}, got {r_b}"
        )

        exp_x = solve_kepler(exp_a, exp_b)
        expected_x_str = f'{exp_x:.6f}'
        actual_x_str = row[3].strip()
        assert re.fullmatch(r'-?\d+\.\d{6}', actual_x_str), (
            f"Row {i+1} 'x' is not printed with exactly 6 decimal places: {row[3]!r}"
        )
        assert actual_x_str == expected_x_str, (
            f"Row {i+1} 'x' mismatch. Expected {expected_x_str}, got {row[3]}"
        )


@pytest.fixture(scope='session')
def executable():
    subprocess.run(
        ['gcc', '-std=c11', '-O2', C_FILE, '-o', EXECUTABLE, '-lm'],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert os.path.isfile(EXECUTABLE), 'gcc did not produce the expected executable.'
    yield EXECUTABLE

    # Leave the task files in their required original state after verification.
    write_input(EXPECTED_INPUTS)
    try:
        run_program()
    except Exception:
        pass


def test_c_file_exists():
    """Check if the C source file was created."""
    assert os.path.exists(C_FILE), f'Expected C program at {C_FILE} is missing.'
    assert os.path.isfile(C_FILE), f'Path {C_FILE} is not a file.'


def test_training_data_exists_and_correct(executable):
    """Compile and run the submitted program on the required observations."""
    write_input(EXPECTED_INPUTS)
    run_program()
    read_and_check_rows(EXPECTED_INPUTS)


def test_program_processes_unseen_csv_rows(executable):
    """Ensure the C program actually reads and processes arbitrary input rows."""
    rng = random.SystemRandom()
    dynamic_inputs = []
    for i in range(8):
        row_id = rng.randrange(1000, 1000000)
        a = round(rng.uniform(0.001, 0.949), 9)
        b = round(rng.uniform(0.01, 6.20), 9)
        dynamic_inputs.append((row_id, a, b))

    write_input(dynamic_inputs)
    run_program()
    read_and_check_rows(dynamic_inputs)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
