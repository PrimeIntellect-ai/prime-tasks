#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import subprocess

import numpy as np
import pytest


def test_generate_data_script_exists():
    assert os.path.exists('/home/user/generate_data.py'), "generate_data.py is missing"


def test_test_generator_script_exists():
    assert os.path.exists('/home/user/test_generator.py'), "test_generator.py is missing"
    with open('/home/user/test_generator.py', 'r') as f:
        content = f.read()
        assert 'pytest' in content or 'test' in content, "test_generator.py does not look like a test script"
        assert '0.05' in content, "test_generator.py does not check for the 0.05 tolerance"


def test_synthetic_data_csv():
    csv_path = '/home/user/synthetic_data.csv'
    assert os.path.exists(csv_path), "synthetic_data.csv is missing"

    with open(csv_path, 'r') as f:
        lines = f.readlines()

    assert len(lines) == 100001, f"Expected 100001 lines in synthetic_data.csv, found {len(lines)}"
    assert lines[0].strip() == 'f1,f2,f3', f"Expected header 'f1,f2,f3', found '{lines[0].strip()}'"

    first_data = lines[1].strip().split(',')
    assert len(first_data) == 3, "Data rows should have 3 columns"
    try:
        [float(x) for x in first_data]
    except ValueError:
        pytest.fail("Data rows do not contain valid floats")


def test_test_results_log():
    log_path = '/home/user/test_results.log'
    assert os.path.exists(log_path), "test_results.log is missing"

    with open(log_path, 'r') as f:
        content = f.read().lower()

    assert 'passed' in content or 'pass' in content, "test_results.log does not indicate a passing test"
    assert 'failed' not in content, "test_results.log indicates a failing test"


def test_generation_and_regression_test_are_real():
    generator_path = '/home/user/generate_data.py'
    test_path = '/home/user/test_generator.py'
    csv_path = '/home/user/synthetic_data.csv'

    with open(generator_path, 'r') as f:
        generator_source = f.read()
    assert 'cholesky' in generator_source.lower(), "generate_data.py does not use Cholesky decomposition"
    assert re.search(r'\bseed\s*\(\s*42\s*\)', generator_source), "generate_data.py does not set the NumPy seed to 42"

    with open(test_path, 'r') as f:
        test_source = f.read()
    ast_tree = ast.parse(test_source, filename=test_path)
    assert any(isinstance(node, ast.Assert) for node in ast.walk(ast_tree)), "test_generator.py contains no assertion"
    lowered = test_source.lower()
    assert 'target_cov.json' in lowered, "test_generator.py does not load the target covariance"
    assert ('np.cov' in lowered or 'numpy.cov' in lowered or
            re.search(r'\b\w*cov(?:ariance)?\w*\b', lowered)), \
        "test_generator.py does not appear to calculate an empirical covariance"

    def run_generator():
        result = subprocess.run(
            ['python3', generator_path], cwd='/home/user',
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=120
        )
        assert result.returncode == 0, "generate_data.py failed:\n" + result.stdout
        assert os.path.isfile(csv_path), "generate_data.py did not create synthetic_data.csv"
        with open(csv_path, 'rb') as f:
            return f.read()

    first_output = run_generator()
    second_output = run_generator()
    assert first_output == second_output, "Generation is not deterministic despite the required seed"

    lines = second_output.decode('utf-8').splitlines()
    assert len(lines) == 100001, f"Expected 100001 lines in generated CSV, found {len(lines)}"
    assert lines[0] == 'f1,f2,f3', "Generated CSV has the wrong header"
    number = re.compile(r'^[-+]?(?:\d+\.\d{6}|nan|inf|-inf)$', re.IGNORECASE)
    for row_number, line in enumerate(lines[1:], start=2):
        fields = line.split(',')
        assert len(fields) == 3, f"CSV row {row_number} does not have 3 columns"
        assert all(number.fullmatch(field) for field in fields), \
            f"CSV row {row_number} is not written with 6 decimal places"

    data = np.loadtxt(csv_path, delimiter=',', skiprows=1)
    assert data.shape == (100000, 3), f"Generated data has shape {data.shape}, expected (100000, 3)"
    assert np.isfinite(data).all(), "Generated data contains non-finite values"

    with open('/home/user/target_cov.json', 'r') as f:
        target = np.asarray(json.load(f), dtype=float)
    empirical = np.cov(data, rowvar=False)
    differences = np.abs(empirical - target)
    assert np.all(differences < 0.05), \
        f"Empirical covariance is outside the strict 0.05 tolerance:\n{empirical}\nDifferences:\n{differences}"
    assert np.all(np.abs(data.mean(axis=0)) < 0.05), \
        f"Generated variables are not empirically zero-mean: {data.mean(axis=0)}"

    result = subprocess.run(
        ['python3', '-m', 'pytest', test_path], cwd='/home/user',
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=120
    )
    assert result.returncode == 0, "The submitted pytest regression test failed:\n" + result.stdout
    assert re.search(r'\b[1-9]\d* passed\b', result.stdout.lower()), \
        "pytest did not collect and pass any submitted tests:\n" + result.stdout

    # Restore and revalidate the required generated artifact in case the test changed it.
    restored = run_generator()
    assert restored == second_output, "Running the regression test altered deterministic generation"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
