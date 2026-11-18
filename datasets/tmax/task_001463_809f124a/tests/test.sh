#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os

import numpy as np
import pandas as pd
from scipy.optimize import minimize

RAW_FILE = '/home/user/spectra_raw.csv'
PURE_FILE = '/home/user/pure_spectra.csv'


def expected_results():
    raw = pd.read_csv(RAW_FILE)
    pure = pd.read_csv(PURE_FILE).set_index('species').loc[['A', 'B', 'C']]

    times = raw['time'].to_numpy(dtype=float)
    M = raw.drop(columns=['time']).to_numpy(dtype=float)
    S = pure.to_numpy(dtype=float)

    singular_values = np.linalg.svd(M, full_matrices=False, compute_uv=False)[:3]

    C_extracted, _, _, _ = np.linalg.lstsq(S.T, M.T, rcond=None)
    C_extracted = C_extracted.T
    A_ex, B_ex, C_ex = C_extracted.T
    A0_ex = float(C_extracted[0].sum())

    def objective(k):
        k1, k2 = map(float, k)
        if k1 == k2:
            # Continuous limit of the stated consecutive-reaction formulas.
            exp_term = np.exp(-k1 * times)
            A_pred = A0_ex * exp_term
            B_pred = A0_ex * k1 * times * exp_term
            C_pred = A0_ex * (1.0 - exp_term * (1.0 + k1 * times))
        else:
            A_pred = A0_ex * np.exp(-k1 * times)
            B_pred = A0_ex * (k1 / (k2 - k1)) * (
                np.exp(-k1 * times) - np.exp(-k2 * times)
            )
            C_pred = A0_ex * (
                1.0
                - (
                    k2 * np.exp(-k1 * times)
                    - k1 * np.exp(-k2 * times)
                ) / (k2 - k1)
            )

        return float(
            np.sum((A_pred - A_ex) ** 2)
            + np.sum((B_pred - B_ex) ** 2)
            + np.sum((C_pred - C_ex) ** 2)
        )

    result = minimize(objective, [0.1, 0.1], method='Nelder-Mead')
    assert result.success, f'Reference optimization failed: {result.message}'
    kinetics = {'k1': round(float(result.x[0]), 4), 'k2': round(float(result.x[1]), 4)}
    return singular_values, kinetics


EXPECTED_SVD, EXPECTED_KINETICS = expected_results()


def test_svd_top3():
    user_file = '/home/user/svd_top3.txt'
    assert os.path.exists(user_file), (
        f'File {user_file} does not exist. The task requires saving the top 3 singular values here.'
    )

    with open(user_file, 'r') as f:
        user_content = f.read().strip()

    user_vals = [v.strip() for v in user_content.split(',')]
    assert len(user_vals) == 3, (
        f'Expected exactly 3 comma-separated values in {user_file}, but found {len(user_vals)}.'
    )

    for i, (user_value, expected_value) in enumerate(zip(user_vals, EXPECTED_SVD)):
        try:
            user_float = float(user_value)
        except ValueError:
            assert False, f"Value '{user_value}' in {user_file} is not a valid float."

        assert math.isclose(user_float, float(expected_value), abs_tol=1e-3), (
            f'Singular value {i + 1} mismatch: expected {expected_value:.4f}, got {user_float}'
        )


def test_kinetics():
    user_file = '/home/user/kinetics.json'
    assert os.path.exists(user_file), (
        f'File {user_file} does not exist. The task requires saving the fitted parameters here.'
    )

    with open(user_file, 'r') as f:
        try:
            user_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f'File {user_file} does not contain valid JSON.'

    for key in ['k1', 'k2']:
        assert key in user_data, f"Key '{key}' is missing from {user_file}."
        user_value = user_data[key]
        expected_value = EXPECTED_KINETICS[key]

        assert isinstance(user_value, (int, float)), (
            f"Value for '{key}' in {user_file} must be a number."
        )
        assert math.isclose(user_value, expected_value, abs_tol=0.0005), (
            f"Value for '{key}' mismatch: expected {expected_value}, got {user_value}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
