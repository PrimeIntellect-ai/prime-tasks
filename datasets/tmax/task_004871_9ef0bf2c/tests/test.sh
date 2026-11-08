#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import csv
import runpy
import tempfile
from unittest import mock

import pytest
import numpy as np
import scipy.linalg

REPORT_FILE = "/home/user/stability_report.json"
DATA_FILE = "/home/user/data.csv"
SCRIPT_FILE = "/home/user/fit_model.py"


def expected_matrix(N):
    dx = 1.0 / (N - 1)
    A = np.zeros((N, N))
    for i in range(N):
        A[i, i] = 2.0 / dx
        if i > 0:
            A[i, i - 1] = -1.0 / dx
        if i < N - 1:
            A[i, i + 1] = -1.0 / dx
    A[0, 0] = 1.0 / dx
    A[0, 1] = 0.0
    A[N - 1, N - 1] = 1.0 / dx
    A[N - 1, N - 2] = 0.0
    return A


def expected_load(N, data_file):
    b = np.zeros(N)
    with open(data_file, 'r') as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            x_val, w = float(row[0]), float(row[1])
            idx = int(round(x_val * (N - 1)))
            b[idx] += w
    return b


def deterministic_solve(N, data_file):
    A = expected_matrix(N)
    b = expected_load(N, data_file)
    c, low = scipy.linalg.cho_factor(A)
    x = scipy.linalg.cho_solve((c, low), b)
    cond_A = np.linalg.cond(A)
    norm_x = np.linalg.norm(x)
    return cond_A, norm_x


def test_00_script_runs_refinement_and_cholesky():
    assert os.path.isfile(SCRIPT_FILE), f"Missing script file: {SCRIPT_FILE}"
    if os.path.exists(REPORT_FILE):
        os.remove(REPORT_FILE)

    factor_calls = []
    solve_calls = []
    real_factor = scipy.linalg.cho_factor
    real_solve = scipy.linalg.cho_solve

    def traced_factor(a, *args, **kwargs):
        factor_calls.append(np.array(a, copy=True))
        return real_factor(a, *args, **kwargs)

    def traced_solve(factor, b, *args, **kwargs):
        solve_calls.append(np.array(b, copy=True))
        return real_solve(factor, b, *args, **kwargs)

    old_cwd = os.getcwd()
    try:
        os.chdir('/home/user')
        with mock.patch('scipy.linalg.cho_factor', side_effect=traced_factor), \
             mock.patch('scipy.linalg.cho_solve', side_effect=traced_solve), \
             mock.patch('numpy.linalg.solve', side_effect=AssertionError(
                 'Generic numpy.linalg.solve must not be used')):
            runpy.run_path(SCRIPT_FILE, run_name='__main__')
    finally:
        os.chdir(old_cwd)

    assert os.path.isfile(REPORT_FILE), "Running fit_model.py did not create stability_report.json"
    for N in (10, 20):
        A_expected = expected_matrix(N)
        b_expected = expected_load(N, DATA_FILE)
        assert any(a.shape == (N, N) and np.array_equal(a, A_expected)
                   for a in factor_calls), f"N={N} matrix was not passed to cho_factor"
        assert any(b.shape == (N,) and np.array_equal(b, b_expected)
                   for b in solve_calls), f"N={N} ordered load vector was not passed to cho_solve"


def test_assemble_and_solve_uses_ordered_load_and_cholesky_result():
    assert os.path.isfile(SCRIPT_FILE), f"Missing script file: {SCRIPT_FILE}"

    with tempfile.NamedTemporaryFile('w', suffix='.csv', delete=False) as f:
        custom_data = f.name
        f.write('x,weight\n')
        # All three values map to the same node. This order produces 1.0;
        # reordering the floating-point reduction can produce 0.0.
        f.write('0.4,10000000000000000\n')
        f.write('0.4,-10000000000000000\n')
        f.write('0.4,1\n')
        f.write('0.8,2.5\n')

    factor_calls = []
    solve_calls = []
    sentinel = np.linspace(100.0, 109.0, 10)

    def fake_factor(a, *args, **kwargs):
        factor_calls.append(np.array(a, copy=True))
        return np.array(a, copy=True), False

    def fake_solve(factor, b, *args, **kwargs):
        solve_calls.append(np.array(b, copy=True))
        return sentinel.copy()

    namespace = {}
    try:
        with mock.patch('scipy.linalg.cho_factor', side_effect=fake_factor), \
             mock.patch('scipy.linalg.cho_solve', side_effect=fake_solve), \
             mock.patch('numpy.linalg.solve', side_effect=AssertionError(
                 'Generic numpy.linalg.solve must not be used')):
            namespace = runpy.run_path(SCRIPT_FILE, run_name='fit_model_under_test')
            assert 'assemble_and_solve' in namespace, "Missing assemble_and_solve function"
            result = namespace['assemble_and_solve'](10, custom_data)
    finally:
        os.unlink(custom_data)

    assert isinstance(result, tuple) and len(result) == 2, \
        "assemble_and_solve must return (A, x)"
    returned_A, returned_x = result
    expected_A = expected_matrix(10)
    expected_b = np.zeros(10)
    expected_b[int(round(0.4 * 9))] = 1.0
    expected_b[int(round(0.8 * 9))] = 2.5

    assert len(factor_calls) == 1, "assemble_and_solve must call cho_factor once"
    assert len(solve_calls) == 1, "assemble_and_solve must call cho_solve once"
    assert np.array_equal(factor_calls[0], expected_A), "Incorrect matrix passed to cho_factor"
    assert np.array_equal(solve_calls[0], expected_b), \
        "Load vector was not accumulated in exact input order"
    assert np.array_equal(returned_A, expected_A), "assemble_and_solve returned an incorrect matrix"
    assert np.array_equal(returned_x, sentinel), \
        "assemble_and_solve did not return the solution produced by cho_solve"


def test_json_exists_and_structure():
    assert os.path.isfile(REPORT_FILE), f"Missing stability report file: {REPORT_FILE}"

    with open(REPORT_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file stability_report.json is not valid JSON.")

    assert "N_10" in data, "Missing 'N_10' key in the JSON report."
    assert "N_20" in data, "Missing 'N_20' key in the JSON report."

    for key in ["N_10", "N_20"]:
        assert "cond_A" in data[key], f"Missing 'cond_A' under {key}."
        assert "norm_x" in data[key], f"Missing 'norm_x' under {key}."
        assert isinstance(data[key]["cond_A"], (int, float)), f"'cond_A' under {key} must be a number."
        assert isinstance(data[key]["norm_x"], (int, float)), f"'norm_x' under {key} must be a number."


def test_json_values():
    assert os.path.isfile(DATA_FILE), f"Missing data file: {DATA_FILE}"
    assert os.path.isfile(REPORT_FILE), f"Missing stability report file: {REPORT_FILE}"

    with open(REPORT_FILE, 'r') as f:
        data = json.load(f)

    expected_cond_10, expected_norm_10 = deterministic_solve(10, DATA_FILE)
    expected_cond_20, expected_norm_20 = deterministic_solve(20, DATA_FILE)

    assert math.isclose(data["N_10"]["cond_A"], expected_cond_10, rel_tol=1e-5), \
        f"N_10 cond_A mismatch. Expected ~{expected_cond_10}, got {data['N_10']['cond_A']}"
    assert math.isclose(data["N_10"]["norm_x"], expected_norm_10, rel_tol=1e-5), \
        f"N_10 norm_x mismatch. Expected ~{expected_norm_10}, got {data['N_10']['norm_x']}"
    assert math.isclose(data["N_20"]["cond_A"], expected_cond_20, rel_tol=1e-5), \
        f"N_20 cond_A mismatch. Expected ~{expected_cond_20}, got {data['N_20']['cond_A']}"
    assert math.isclose(data["N_20"]["norm_x"], expected_norm_20, rel_tol=1e-5), \
        f"N_20 norm_x mismatch. Expected ~{expected_norm_20}, got {data['N_20']['norm_x']}"


def test_cholesky_used_in_script():
    assert os.path.isfile(SCRIPT_FILE), f"Missing script file: {SCRIPT_FILE}"

    with open(SCRIPT_FILE, 'r') as f:
        content = f.read()

    assert "cho_factor" in content, "The script must use scipy.linalg.cho_factor."
    assert "cho_solve" in content, "The script must use scipy.linalg.cho_solve."
    assert "set(" not in content, "The script should not use sets for aggregation to ensure determinism."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
