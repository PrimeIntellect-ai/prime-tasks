#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
import tempfile

APP_DIR = '/home/user/app'
EXECUTABLE = os.path.join(APP_DIR, 'poly_fit')
SOURCE = os.path.join(APP_DIR, 'poly_fit.c')
OUTPUT = os.path.join(APP_DIR, 'output.txt')


def solve_system(M, B):
    n = len(M)
    M = [row[:] for row in M]
    B = B[:]
    for i in range(n):
        for j in range(i + 1, n):
            factor = M[j][i] / M[i][i]
            for k in range(i, n):
                M[j][k] -= factor * M[i][k]
            B[j] -= factor * B[i]
    X = [0.0] * n
    for i in range(n - 1, -1, -1):
        X[i] = B[i]
        for j in range(i + 1, n):
            X[i] -= M[i][j] * X[j]
        X[i] /= M[i][i]
    return X


def calculate_expected(rows):
    n_coeffs = 4
    ATA = [[0.0] * n_coeffs for _ in range(n_coeffs)]
    ATB = [0.0] * n_coeffs

    for x, y in rows:
        px = [1.0, x, x ** 2, x ** 3]
        for r in range(n_coeffs):
            ATB[r] += px[r] * y
            for c in range(n_coeffs):
                ATA[r][c] += px[r] * px[c]

    for i in range(n_coeffs):
        ATA[i][i] += 1e-4

    coeffs = solve_system(ATA, ATB)
    integral = sum(coeffs[i] * (10.0 ** (i + 1)) / (i + 1) for i in range(4))
    return coeffs, integral


def get_expected_results():
    data_path = os.path.join(APP_DIR, 'data.csv')
    if not os.path.exists(data_path):
        return None, None

    rows = []
    with open(data_path, 'r') as f:
        for line in f:
            parts = line.strip().split(',')
            if len(parts) == 2:
                rows.append((float(parts[0]), float(parts[1])))
    return calculate_expected(rows)


def parse_exact_output(path):
    with open(path, 'r') as f:
        content = f.read()
    pattern = (
        r'Coefficients:\n'
        r'c0 = ([-+]?\d+\.\d{4})\n'
        r'c1 = ([-+]?\d+\.\d{4})\n'
        r'c2 = ([-+]?\d+\.\d{4})\n'
        r'c3 = ([-+]?\d+\.\d{4})\n'
        r'Integral\(0 to 10\): ([-+]?\d+\.\d{4})\n?'
    )
    match = re.fullmatch(pattern, content)
    assert match, 'Program output does not have the required exact format with four decimal places'
    values = [float(v) for v in match.groups()]
    assert all(math.isfinite(v) for v in values), 'Program produced a non-finite result'
    return values[:4], values[4]


def run_case(binary, rows):
    with tempfile.TemporaryDirectory() as workdir:
        data_path = os.path.join(workdir, 'data.csv')
        with open(data_path, 'w') as f:
            for x, y in rows:
                f.write(f'{x:.17g}, {y:.17g}\n')

        result = subprocess.run(
            [binary], cwd=workdir, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=10
        )
        assert result.returncode == 0, (
            f'{binary} failed with exit code {result.returncode}: {result.stderr}'
        )
        output_path = os.path.join(workdir, 'output.txt')
        assert os.path.isfile(output_path), f'{binary} did not create output.txt when run'
        actual_coeffs, actual_integral = parse_exact_output(output_path)
        expected_coeffs, expected_integral = calculate_expected(rows)

        for i in range(4):
            assert abs(actual_coeffs[i] - expected_coeffs[i]) < 0.00011, (
                f'{binary} produced an incorrect regularized coefficient c{i} on a verification dataset'
            )
        assert abs(actual_integral - expected_integral) < 0.00011, (
            f'{binary} produced an incorrect analytical integral on a verification dataset'
        )


def make_verification_rows(rng):
    base = rng.uniform(0.85, 1.15)
    true_coeffs = [rng.uniform(-3.0, 3.0) for _ in range(4)]
    rows = []
    for i in range(12):
        x = base + (i - 5.5) * 0.0007 + rng.uniform(-0.00001, 0.00001)
        y = sum(true_coeffs[j] * x ** j for j in range(4))
        y += rng.uniform(-0.01, 0.01)
        rows.append((x, y))
    return rows


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), "The compiled executable 'poly_fit' is missing. Did you compile the program?"


def test_executable_is_compiled_program():
    assert os.access(EXECUTABLE, os.X_OK), "The 'poly_fit' file is not executable"
    with open(EXECUTABLE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "The 'poly_fit' artifact is not a compiled ELF executable"


def test_source_compiles_and_both_artifacts_handle_derived_inputs():
    assert os.path.isfile(SOURCE), 'poly_fit.c is missing'
    rng = random.SystemRandom()
    cases = [make_verification_rows(rng) for _ in range(2)]

    with tempfile.TemporaryDirectory() as builddir:
        rebuilt = os.path.join(builddir, 'poly_fit_from_source')
        result = subprocess.run(
            ['gcc', '-O2', SOURCE, '-o', rebuilt, '-lm'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert result.returncode == 0, f'poly_fit.c does not compile as required: {result.stderr}'

        for rows in cases:
            run_case(rebuilt, rows)
            run_case(EXECUTABLE, rows)


def test_run_executable_on_provided_data():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [EXECUTABLE], cwd=APP_DIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"The compiled executable failed on data.csv with exit code {result.returncode}: {result.stderr}"
    )


def test_output_file_exists():
    assert os.path.isfile(OUTPUT), "The 'output.txt' file is missing. Did you run the program and redirect output?"


def test_output_results():
    output_path = OUTPUT
    assert os.path.isfile(output_path), 'output.txt not found'

    with open(output_path, 'r') as f:
        content = f.read()

    c_matches = re.findall(r'c(\d)\s*=\s*([-+]?\d*\.\d+)', content)
    assert len(c_matches) == 4, 'Could not find exactly 4 coefficients in output.txt in the expected format (e.g., c0 = 1.2345)'

    parsed_coeffs = [0.0] * 4
    for idx_str, val_str in c_matches:
        idx = int(idx_str)
        if 0 <= idx <= 3:
            parsed_coeffs[idx] = float(val_str)

    int_match = re.search(r'Integral\(0 to 10\):\s*([-+]?\d*\.\d+)', content)
    assert int_match, "Could not find 'Integral(0 to 10): [value]' in output.txt"
    parsed_integral = float(int_match.group(1))

    expected_coeffs, expected_integral = get_expected_results()
    assert expected_coeffs is not None, 'Failed to compute expected results because data.csv is missing'

    for i in range(4):
        assert abs(parsed_coeffs[i] - expected_coeffs[i]) < 0.005, f'Coefficient c{i} ({parsed_coeffs[i]}) does not match the expected regularized value ({expected_coeffs[i]:.4f}). Did you add 1e-4 to the diagonal of ATA?'

    assert abs(parsed_integral - expected_integral) < 0.005, f'Integral ({parsed_integral}) does not match the expected value ({expected_integral:.4f}). Check your integrate_poly implementation.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
