#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
from decimal import Decimal

import numpy as np
from scipy.optimize import curve_fit

DATA_PATH = '/home/user/profiling_data.csv'
RESULT_PATH = '/home/user/model_results.json'


def expected_rows():
    random.seed(42)
    rows = []
    for N in [1000, 5000, 10000, 20000, 30000]:
        for C in [1, 2, 4, 8, 16, 32]:
            T = 0.5 * (N / C) + 2.0 * (C ** 1.5)
            T_noisy = T + random.uniform(-0.01, 0.01) * T
            if random.random() < 0.15:
                rows.append((N, C, T_noisy * 5.0, 'Timeout'))
            else:
                rows.append((N, C, T_noisy, 'Success'))
    return rows


def load_and_validate_profiling_data():
    assert os.path.isfile(DATA_PATH), f'File not found: {DATA_PATH}'
    with open(DATA_PATH, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['N', 'C', 'Time', 'Status'], 'Unexpected profiling-data columns.'
        actual = list(reader)

    expected = expected_rows()
    assert len(actual) == len(expected), 'The profiling dataset was modified.'
    parsed = []
    for row, (exp_n, exp_c, exp_t, exp_status) in zip(actual, expected):
        try:
            n = int(row['N'])
            concurrency = int(row['C'])
            elapsed = float(row['Time'])
        except (TypeError, ValueError):
            assert False, 'The profiling dataset contains invalid numeric data.'
        assert n == exp_n and concurrency == exp_c
        assert row['Status'] == exp_status
        assert math.isclose(elapsed, exp_t, rel_tol=1e-12, abs_tol=1e-12), 'The profiling dataset was modified.'
        parsed.append((n, concurrency, elapsed, row['Status']))
    return parsed


def fitted_result(rows):
    successful = [row for row in rows if row[3] == 'Success']
    n_values = np.asarray([row[0] for row in successful], dtype=float)
    c_values = np.asarray([row[1] for row in successful], dtype=float)
    times = np.asarray([row[2] for row in successful], dtype=float)

    def model(inputs, a, b, c):
        n, concurrency = inputs
        return a * n / concurrency + b * concurrency ** c

    params, _ = curve_fit(
        model,
        (n_values, c_values),
        times,
        p0=[1.0, 1.0, 1.0],
        bounds=([0.1, 0.1, 0.1], [5.0, 5.0, 5.0]),
    )
    a, b, c = map(float, params)
    optimal_c = max(1.0, (a * 50000.0 / (b * c)) ** (1.0 / (c + 1.0)))
    return {
        'a': float(f'{a:.4f}'),
        'b': float(f'{b:.4f}'),
        'c': float(f'{c:.4f}'),
        'optimal_C': float(f'{optimal_c:.4f}'),
    }


def test_model_results_exists():
    assert os.path.isfile(RESULT_PATH), f'File not found: {RESULT_PATH}'


def test_model_results_content():
    rows = load_and_validate_profiling_data()
    expected = fitted_result(rows)

    with open(RESULT_PATH, 'r') as f:
        raw = f.read()
    try:
        data = json.loads(raw)
        precise_data = json.loads(raw, parse_float=Decimal, parse_int=Decimal)
    except json.JSONDecodeError:
        assert False, f'File {RESULT_PATH} is not valid JSON.'

    expected_keys = {'a', 'b', 'c', 'optimal_C'}
    actual_keys = set(data.keys())
    assert actual_keys == expected_keys, f'Expected keys {expected_keys}, but got {actual_keys}'

    for key in expected_keys:
        assert isinstance(precise_data[key], Decimal), f"Value '{key}' must be a JSON number."
        assert precise_data[key].as_tuple().exponent == -4, f"Value '{key}' must have exactly 4 decimal places."

    try:
        a = float(data['a'])
        b = float(data['b'])
        c = float(data['c'])
        opt_c = float(data['optimal_C'])
    except (ValueError, TypeError):
        assert False, 'All values in the JSON must be numbers.'

    assert all(math.isfinite(v) for v in (a, b, c, opt_c)), 'All values must be finite.'

    # Preserve the original broad sanity assertions.
    assert 0.45 <= a <= 0.55, f"Parameter 'a' out of bounds: {a}. Expected around 0.5."
    assert 1.9 <= b <= 2.1, f"Parameter 'b' out of bounds: {b}. Expected around 2.0."
    assert 1.45 <= c <= 1.55, f"Parameter 'c' out of bounds: {c}. Expected around 1.5."
    assert 36.5 <= opt_c <= 38.0, f'Optimal C out of bounds: {opt_c}. Expected around 37.28.'

    submitted = {'a': a, 'b': b, 'c': c, 'optimal_C': opt_c}
    for key in expected_keys:
        assert math.isclose(submitted[key], expected[key], rel_tol=0.0, abs_tol=1e-9), (
            f"Incorrect {key}: got {submitted[key]:.4f}, expected {expected[key]:.4f} "
            'from the successful profiling runs.'
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
