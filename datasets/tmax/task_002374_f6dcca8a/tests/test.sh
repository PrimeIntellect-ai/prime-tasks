#!/bin/bash
set +e
mkdir -p /logs/verifier

# The requested artifact must be a real Go source file, not a symlink.
if [ ! -f /home/user/analyze.go ] || [ -L /home/user/analyze.go ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

# Ensure results.json is freshly produced by executing the submitted program.
rm -rf /home/user/results.json
(
    cd /home/user || exit 1
    timeout 60s go run analyze.go
)
if [ $? -ne 0 ] || [ ! -f /home/user/results.json ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import stat
import secrets
import subprocess

ANALYZE = '/home/user/analyze.go'
RESULTS = '/home/user/results.json'
WT_DATA = '/home/user/wt_data.csv'
MUT_DATA = '/home/user/mut_data.csv'


def transpose(A):
    return [[A[i][j] for i in range(len(A))] for j in range(len(A[0]))]


def mat_mul(A, B):
    m = len(A)
    n = len(A[0])
    p = len(B[0])
    C = [[0] * p for _ in range(m)]
    for i in range(m):
        for j in range(p):
            for k in range(n):
                C[i][j] += A[i][k] * B[k][j]
    return C


def invert_2x2(M):
    a, b = M[0][0], M[0][1]
    c, d = M[1][0], M[1][1]
    det = a * d - b * c
    return [[d / det, -b / det], [-c / det, a / det]]


def solve_ridge(X, Y, lam=0.05):
    XT = transpose(X)
    XTX = mat_mul(XT, X)
    XTX[0][0] += lam
    XTX[1][1] += lam
    inv = invert_2x2(XTX)
    XTY = mat_mul(XT, Y)
    theta = mat_mul(inv, XTY)
    return [theta[0][0], theta[1][0]]


def read_data(filepath):
    X = []
    Y = []
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            X.append([float(row['x1']), float(row['x2'])])
            Y.append([float(row['y'])])
    return X, Y


def expected_results(wt_X, wt_Y, mut_X, mut_Y):
    wt_theta = solve_ridge(wt_X, wt_Y, lam=0.05)
    mut_theta = solve_ridge(mut_X, mut_Y, lam=0.05)

    x1_10, x2_10 = mut_X[9]
    y_10_hat = mut_theta[0] * x1_10 + mut_theta[1] * x2_10
    dy_dt = -0.1 * y_10_hat + mut_theta[0] * x1_10 + mut_theta[1] * x2_10

    sse_h1 = 0
    for i in range(len(wt_Y)):
        y_hat = wt_theta[0] * wt_X[i][0] + wt_theta[1] * wt_X[i][1]
        sse_h1 += (wt_Y[i][0] - y_hat) ** 2

    sum_x1_sq = sum(x[0] ** 2 for x in wt_X)
    sum_x1_y = sum(wt_X[i][0] * wt_Y[i][0] for i in range(len(wt_Y)))
    theta0 = sum_x1_y / (sum_x1_sq + 0.05)

    sse_h0 = 0
    for i in range(len(wt_Y)):
        y_hat = theta0 * wt_X[i][0]
        sse_h0 += (wt_Y[i][0] - y_hat) ** 2

    N = len(wt_Y)
    F = ((sse_h0 - sse_h1) / 1) / (sse_h1 / (N - 2))

    return {
        'wt_theta1': round(wt_theta[0], 4),
        'wt_theta2': round(wt_theta[1], 4),
        'mut_theta1': round(mut_theta[0], 4),
        'mut_theta2': round(mut_theta[1], 4),
        'mut_dy_dt_at_10': round(dy_dt, 4),
        'wt_f_statistic': round(F, 4),
    }


def assert_result_values(expected):
    with open(RESULTS, 'r') as f:
        data = json.load(f)
    for key, expected_val in expected.items():
        actual_val = data.get(key)
        assert actual_val is not None, f'Missing {key} in results.json'
        assert isinstance(actual_val, (int, float)) and not isinstance(actual_val, bool), \
            f'Value for {key} must be numeric'
        assert math.isfinite(actual_val), f'Value for {key} must be finite'
        assert math.isclose(actual_val, expected_val, abs_tol=1e-3), \
            f'Value for {key} is incorrect. Expected ~{expected_val}, got {actual_val}'


def write_dataset(path, rows):
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['t', 'x1', 'x2', 'y'])
        writer.writerows(rows)


def test_analyze_go_is_regular_source_file():
    assert os.path.isfile(ANALYZE), f'Go program missing: {ANALYZE}'
    assert not os.path.islink(ANALYZE), 'analyze.go must not be a symlink'
    assert stat.S_ISREG(os.stat(ANALYZE).st_mode), 'analyze.go must be a regular file'
    assert os.path.getsize(ANALYZE) > 0, 'analyze.go is empty'


def test_results_json_exists_and_valid():
    """Check if results.json exists and contains the required keys."""
    assert os.path.isfile(RESULTS), f'Output file missing: {RESULTS}'

    with open(RESULTS, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, 'results.json is not a valid JSON file.'

    expected_keys = {
        'wt_theta1', 'wt_theta2',
        'mut_theta1', 'mut_theta2',
        'mut_dy_dt_at_10', 'wt_f_statistic'
    }
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f'results.json is missing keys: {missing_keys}'


def test_correct_values():
    """Derive the expected values and assert they match the student's output."""
    wt_X, wt_Y = read_data(WT_DATA)
    mut_X, mut_Y = read_data(MUT_DATA)
    assert_result_values(expected_results(wt_X, wt_Y, mut_X, mut_Y))


def test_program_recomputes_for_unseen_inputs():
    """Execute analyze.go on runtime-generated data to reject hardcoded results."""
    rng = secrets.SystemRandom()
    original_wt = open(WT_DATA, 'rb').read()
    original_mut = open(MUT_DATA, 'rb').read()
    original_results = open(RESULTS, 'rb').read()

    wt_rows = []
    mut_rows = []
    for t in range(1, 11):
        wx1 = t * rng.uniform(0.72, 1.31)
        wx2 = 0.11 * t * t + t * rng.uniform(0.18, 0.63)
        wy = 1.37 * wx1 + 0.84 * wx2 + rng.uniform(-0.22, 0.22)
        wt_rows.append([t, f'{wx1:.8f}', f'{wx2:.8f}', f'{wy:.8f}'])

        mx1 = t * rng.uniform(0.81, 1.19)
        mx2 = mx1 * (1.0 + rng.uniform(-0.0018, 0.0018))
        my = 0.73 * mx1 + 1.21 * mx2 + rng.uniform(-0.08, 0.08)
        mut_rows.append([t, f'{mx1:.8f}', f'{mx2:.8f}', f'{my:.8f}'])

    try:
        write_dataset(WT_DATA, wt_rows)
        write_dataset(MUT_DATA, mut_rows)
        if os.path.lexists(RESULTS):
            os.remove(RESULTS)

        completed = subprocess.run(
            ['go', 'run', 'analyze.go'],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert completed.returncode == 0, \
            f'analyze.go failed on valid unseen data: {completed.stderr}'
        assert os.path.isfile(RESULTS), 'analyze.go did not generate results.json'

        wt_X, wt_Y = read_data(WT_DATA)
        mut_X, mut_Y = read_data(MUT_DATA)
        assert_result_values(expected_results(wt_X, wt_Y, mut_X, mut_Y))
    finally:
        with open(WT_DATA, 'wb') as f:
            f.write(original_wt)
        with open(MUT_DATA, 'wb') as f:
            f.write(original_mut)
        with open(RESULTS, 'wb') as f:
            f.write(original_results)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
