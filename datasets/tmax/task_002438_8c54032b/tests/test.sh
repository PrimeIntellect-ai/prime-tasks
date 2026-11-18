#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import subprocess
import tempfile
import math
import pytest

RESULT = '/home/user/result.json'
STUDENT_CSV = '/home/user/noisy_data.csv'
GEN_SRC = '/home/user/generator.c'
GEN_BIN = '/home/user/generator'


def test_result_json_exists():
    assert os.path.exists(RESULT), f'{RESULT} does not exist.'


def test_result_json_valid():
    with open(RESULT, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{RESULT} is not valid JSON.')

    assert 'converged_N' in data, "Missing 'converged_N' in result.json."
    assert 'ci_lower' in data, "Missing 'ci_lower' in result.json."
    assert 'ci_upper' in data, "Missing 'ci_upper' in result.json."


def build_expected_csv(tmpdir):
    trusted_src = os.path.join(tmpdir, 'trusted_generator.c')
    trusted_bin = os.path.join(tmpdir, 'trusted_generator')
    expected_csv = os.path.join(tmpdir, 'expected_noisy_data.csv')
    source = r'''#include <stdio.h>
#include <stdlib.h>
#include <math.h>

double exact(double x) {
    return sinh(1.0 - x) / sinh(1.0);
}

int main(int argc, char **argv) {
    if (argc != 3) return 1;
    int N = atoi(argv[1]);
    int trials = 100;
    srand(42);
    FILE *f = fopen(argv[2], "w");
    if (!f) return 2;
    for (int t = 0; t < trials; t++) {
        for (int i = 0; i <= N; i++) {
            double x = (double)i / N;
            double val = exact(x);
            double noise = ((double)rand() / RAND_MAX) * 0.2 - 0.1;
            fprintf(f, "%.6f", val + noise);
            if (i < N) fprintf(f, ",");
        }
        fprintf(f, "\n");
    }
    fclose(f);
    return 0;
}
'''
    with open(trusted_src, 'w') as f:
        f.write(source)
    subprocess.run(
        ['gcc', '-O3', trusted_src, '-o', trusted_bin, '-lm'],
        check=True, timeout=30
    )
    subprocess.run([trusted_bin, '20', expected_csv], check=True, timeout=30)
    with open(expected_csv, 'rb') as f:
        return f.read()


def run_home_generator_and_capture(command):
    with open(STUDENT_CSV, 'rb') as f:
        original = f.read()
    try:
        subprocess.run(command, check=True, timeout=30)
        assert os.path.exists(STUDENT_CSV), 'Generator did not create noisy_data.csv.'
        with open(STUDENT_CSV, 'rb') as f:
            return f.read()
    finally:
        with open(STUDENT_CSV, 'wb') as f:
            f.write(original)


def test_generator_pipeline_and_data():
    assert os.path.isfile(GEN_SRC), f'{GEN_SRC} does not exist.'
    assert os.path.isfile(GEN_BIN), f'{GEN_BIN} does not exist.'
    assert os.access(GEN_BIN, os.X_OK), f'{GEN_BIN} is not executable.'
    with open(GEN_BIN, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{GEN_BIN} is not a compiled ELF executable.'
    assert os.path.exists(STUDENT_CSV), f'{STUDENT_CSV} does not exist.'

    with tempfile.TemporaryDirectory() as tmpdir:
        expected = build_expected_csv(tmpdir)
        with open(STUDENT_CSV, 'rb') as f:
            submitted = f.read()
        assert submitted == expected, \
            'noisy_data.csv does not match the fixed-seed N=20 generator output.'

        generated_by_agent_binary = run_home_generator_and_capture([GEN_BIN, '20'])
        assert generated_by_agent_binary == expected, \
            'The submitted generator executable does not produce the required fixed-seed N=20 data.'

        rebuilt_bin = os.path.join(tmpdir, 'rebuilt_generator')
        subprocess.run(
            ['gcc', '-O3', GEN_SRC, '-o', rebuilt_bin, '-lm'],
            check=True, timeout=30
        )
        generated_from_source = run_home_generator_and_capture([rebuilt_bin, '20'])
        assert generated_from_source == expected, \
            'Compiling generator.c does not produce the required fixed-seed N=20 data.'


def test_converged_N_and_confidence_intervals():
    with open(RESULT, 'r') as f:
        data = json.load(f)

    # 1. Check converged_N
    assert data['converged_N'] == 20, \
        f"Expected converged_N to be 20, got {data['converged_N']}."

    # 2. Recompute expected CI
    student_csv = STUDENT_CSV
    assert os.path.exists(student_csv), f'{student_csv} does not exist.'

    with open(student_csv, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 100, \
        f'Expected 100 rows in {student_csv}, found {len(lines)}.'

    parsed_data = []
    for line in lines:
        row = [float(x) for x in line.split(',')]
        assert len(row) == 21, \
            f'Expected 21 columns (N=20) in {student_csv}, found {len(row)}.'
        parsed_data.append(row)

    N = 20
    exact_vals = []
    for i in range(N + 1):
        x = i / N
        val = math.sinh(1.0 - x) / math.sinh(1.0)
        exact_vals.append(val)

    mses = []
    for row in parsed_data:
        mse = sum((r - e) ** 2 for r, e in zip(row, exact_vals)) / len(exact_vals)
        mses.append(mse)

    try:
        import numpy as np
    except ImportError:
        pytest.fail('numpy is not installed, cannot verify bootstrap.')

    mses_np = np.array(mses)
    np.random.seed(42)

    bootstrapped_means = []
    for _ in range(10000):
        sample = np.random.choice(mses_np, size=100, replace=True)
        bootstrapped_means.append(np.mean(sample))

    expected_ci_lower = np.percentile(bootstrapped_means, 2.5)
    expected_ci_upper = np.percentile(bootstrapped_means, 97.5)

    student_ci_lower = data['ci_lower']
    student_ci_upper = data['ci_upper']

    assert abs(student_ci_lower - expected_ci_lower) < 1e-5, \
        f'ci_lower mismatch. Expected ~{expected_ci_lower:.6f}, got {student_ci_lower}'

    assert abs(student_ci_upper - expected_ci_upper) < 1e-5, \
        f'ci_upper mismatch. Expected ~{expected_ci_upper:.6f}, got {student_ci_upper}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
