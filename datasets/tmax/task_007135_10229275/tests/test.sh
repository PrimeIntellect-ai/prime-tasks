#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import subprocess
import sys
from pathlib import Path

SCRIPT = Path('/home/user/prepare_data.py')
CALIBRATION = Path('/home/user/calibration.csv')
RAW = Path('/home/user/raw_features.csv')
OUTPUT = Path('/home/user/corrected_features.csv')


def fit_parameters(calibration_rows):
    # Independent least-squares fit of y = A*x + B*x^3, without an intercept.
    s_x2 = sum(x * x for x, _ in calibration_rows)
    s_x4 = sum(x ** 4 for x, _ in calibration_rows)
    s_x6 = sum(x ** 6 for x, _ in calibration_rows)
    s_xy = sum(x * y for x, y in calibration_rows)
    s_x3y = sum((x ** 3) * y for x, y in calibration_rows)
    determinant = s_x2 * s_x6 - s_x4 * s_x4
    assert abs(determinant) > 1e-15, 'Calibration design matrix is singular.'
    a = (s_xy * s_x6 - s_x3y * s_x4) / determinant
    b = (s_x2 * s_x3y - s_x4 * s_xy) / determinant
    return round(a, 2), round(b, 2)


def solve_expected(y, a, b):
    x_old = y / a
    for iterations in range(1, 10001):
        derivative = a + 3.0 * b * x_old * x_old
        assert derivative != 0.0, 'Unexpected zero derivative in verifier input.'
        x_new = x_old - (a * x_old + b * x_old ** 3 - y) / derivative
        if abs(x_new - x_old) < 1e-5:
            return x_new, iterations
        x_old = x_new
    raise AssertionError('Independent Newton-Raphson solver did not converge.')


def read_numeric_csv(path, expected_header):
    with path.open(newline='') as handle:
        reader = csv.reader(handle)
        rows = list(reader)
    assert rows, f'{path} is empty.'
    assert rows[0] == expected_header, f'Header in {path} is incorrect: {rows[0]}'
    return rows[1:]


def load_inputs():
    calibration = []
    for row in read_numeric_csv(CALIBRATION, ['x_true', 'y_obs']):
        assert len(row) == 2
        calibration.append((float(row[0]), float(row[1])))
    raw = []
    for row in read_numeric_csv(RAW, ['y_obs']):
        assert len(row) == 1
        raw.append(float(row[0]))
    return calibration, raw


def run_submission():
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        [sys.executable, str(SCRIPT)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'{SCRIPT} exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert OUTPUT.exists(), f'Expected output file {OUTPUT} does not exist after running the script.'
    assert OUTPUT.is_file(), f'{OUTPUT} is not a file.'


def validate_results(calibration, raw, require_original_prefixes=False):
    with OUTPUT.open('r', newline='') as handle:
        lines = [line.strip() for line in handle if line.strip()]

    # Preserve the original output assertions.
    assert len(lines) >= 5 if require_original_prefixes else len(lines) >= 2, (
        f'{OUTPUT} does not contain enough lines.'
    )
    assert lines[0] == 'y_obs,x_pred,iterations', f'Header in {OUTPUT} is incorrect.'

    if require_original_prefixes:
        expected_prefixes = [
            '1.7,1.0000,',
            '4.6,2.0000,',
            '18.8,4.0000,',
            '24.832,4.6000,',
        ]
        for i, prefix in enumerate(expected_prefixes):
            line = lines[i + 1]
            assert line.startswith(prefix), (
                f"Line {i + 2} in {OUTPUT} expected to start with '{prefix}', but got '{line}'"
            )
            parts = line.split(',')
            assert len(parts) == 3, f'Line {i + 2} does not have exactly 3 columns.'
            try:
                iterations = int(parts[2])
                assert iterations > 0, (
                    f'Iterations must be greater than 0, got {iterations} on line {i + 2}'
                )
            except ValueError:
                assert False, f'Iterations column on line {i + 2} is not an integer: {parts[2]}'

    rows = read_numeric_csv(OUTPUT, ['y_obs', 'x_pred', 'iterations'])
    assert len(rows) == len(raw), (
        f'Expected exactly {len(raw)} output rows, but found {len(rows)}.'
    )

    a, b = fit_parameters(calibration)
    for index, (row, input_y) in enumerate(zip(rows, raw), start=2):
        assert len(row) == 3, f'Line {index} does not have exactly 3 columns.'
        try:
            output_y = float(row[0])
            output_iterations = int(row[2])
        except ValueError as exc:
            raise AssertionError(f'Line {index} contains a non-numeric field: {row}') from exc

        expected_x, expected_iterations = solve_expected(input_y, a, b)
        assert output_y == input_y, (
            f'Line {index} has y_obs={output_y}, expected {input_y}.'
        )
        assert row[1] == f'{expected_x:.4f}', (
            f'Line {index} has x_pred={row[1]}, expected {expected_x:.4f}.'
        )
        assert output_iterations > 0, (
            f'Iterations must be greater than 0, got {output_iterations} on line {index}.'
        )
        assert output_iterations == expected_iterations, (
            f'Line {index} has iterations={output_iterations}, expected {expected_iterations}.'
        )


def test_script_executes_and_implements_regression_and_newton_raphson():
    assert SCRIPT.exists(), f'Expected script {SCRIPT} does not exist.'
    assert SCRIPT.is_file(), f'{SCRIPT} is not a file.'

    original_calibration = CALIBRATION.read_bytes()
    original_raw = RAW.read_bytes()
    saved_output = None

    try:
        # Execute against the instructed data and validate the original fixed assertions
        # as well as independently computed iteration counts.
        calibration, raw = load_inputs()
        run_submission()
        assert CALIBRATION.read_bytes() == original_calibration, 'The script modified calibration.csv.'
        assert RAW.read_bytes() == original_raw, 'The script modified raw_features.csv.'
        validate_results(calibration, raw, require_original_prefixes=True)
        saved_output = OUTPUT.read_bytes()

        # Exercise the submitted script on unpredictable coefficients and observations.
        rng = random.SystemRandom()
        true_a = rng.randint(111, 229) / 100.0
        true_b = rng.randint(4, 31) / 100.0
        calibration_x = [0.5, 1.0, 1.75, 2.5, 3.5, 4.75]
        dynamic_calibration = [(x, true_a * x + true_b * x ** 3) for x in calibration_x]
        roots = [rng.randint(65, 550) / 100.0 for _ in range(6)]
        dynamic_raw = [true_a * x + true_b * x ** 3 for x in roots]

        with CALIBRATION.open('w', newline='') as handle:
            writer = csv.writer(handle, lineterminator='\n')
            writer.writerow(['x_true', 'y_obs'])
            for x, y in dynamic_calibration:
                writer.writerow([format(x, '.12g'), format(y, '.15g')])
        with RAW.open('w', newline='') as handle:
            writer = csv.writer(handle, lineterminator='\n')
            writer.writerow(['y_obs'])
            for y in dynamic_raw:
                writer.writerow([format(y, '.15g')])

        actual_calibration, actual_raw = load_inputs()
        dynamic_calibration_bytes = CALIBRATION.read_bytes()
        dynamic_raw_bytes = RAW.read_bytes()
        run_submission()
        assert CALIBRATION.read_bytes() == dynamic_calibration_bytes, 'The script modified calibration.csv.'
        assert RAW.read_bytes() == dynamic_raw_bytes, 'The script modified raw_features.csv.'
        validate_results(actual_calibration, actual_raw)
    finally:
        CALIBRATION.write_bytes(original_calibration)
        RAW.write_bytes(original_raw)
        if saved_output is not None:
            OUTPUT.write_bytes(saved_output)
        elif OUTPUT.exists():
            OUTPUT.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
