#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess
import pytest

PROJECT = '/home/user/ml_pipeline'
GO_FILE = os.path.join(PROJECT, 'process.go')
MOD_FILE = os.path.join(PROJECT, 'go.mod')
RAW_FILE = '/home/user/raw_spectra.csv'
RESULT_FILE = '/home/user/svd_result.txt'
BINARY = '/tmp/ml_pipeline_process'


def test_go_project_setup():
    """Test that the Go project files exist and declare the required module/dependency."""
    assert os.path.exists(GO_FILE), f"Go source file {GO_FILE} is missing."
    assert os.path.isfile(GO_FILE), f"Path {GO_FILE} is not a file."

    assert os.path.exists(MOD_FILE), f"Go module file {MOD_FILE} is missing."
    assert os.path.isfile(MOD_FILE), f"Path {MOD_FILE} is not a file."

    with open(MOD_FILE, 'r') as f:
        mod_content = f.read()
    assert 'module ml_pipeline' in mod_content, "The go.mod file does not define the module 'ml_pipeline'."
    assert 'gonum.org/v1/gonum' in mod_content, "The go.mod file does not require 'gonum.org/v1/gonum'."

    with open(GO_FILE, 'r') as f:
        source = f.read()
    assert 'gonum.org/v1/gonum' in source, "process.go does not import the required gonum library."


def test_svd_result():
    """Preserve the original assertion on the result produced by the agent."""
    assert os.path.exists(RESULT_FILE), f"Result file {RESULT_FILE} is missing."
    assert os.path.isfile(RESULT_FILE), f"Path {RESULT_FILE} is not a file."

    with open(RESULT_FILE, 'r') as f:
        content = f.read().strip()

    assert content != "", f"Result file {RESULT_FILE} is empty."

    try:
        actual_val = float(content)
    except ValueError:
        pytest.fail(f"Content of {RESULT_FILE} is not a valid float: '{content}'")

    expected_val = 183.0232
    assert math.isclose(actual_val, expected_val, rel_tol=1e-4, abs_tol=1e-3), \
        f"Expected SVD result to be close to {expected_val}, but got {actual_val}."

    if '.' in content:
        decimals = len(content.split('.')[1])
        assert decimals == 4, f"Expected exactly 4 decimal places, but found {decimals} in '{content}'."
    else:
        pytest.fail(f"Expected float with 4 decimal places, but got '{content}'.")


def largest_singular_value(matrix):
    """Compute the largest singular value from the 10x10 Gram matrix."""
    rows = len(matrix)
    cols = len(matrix[0])
    gram = [[sum(matrix[i][k] * matrix[j][k] for k in range(cols))
             for j in range(rows)] for i in range(rows)]

    v = [float(i + 1) for i in range(rows)]
    norm = math.sqrt(sum(x * x for x in v))
    v = [x / norm for x in v]

    for _ in range(20000):
        w = [sum(gram[i][j] * v[j] for j in range(rows)) for i in range(rows)]
        norm = math.sqrt(sum(x * x for x in w))
        assert norm > 0.0
        new_v = [x / norm for x in w]
        if max(abs(new_v[i] - v[i]) for i in range(rows)) < 1e-14:
            v = new_v
            break
        v = new_v

    eigenvalue = sum(v[i] * sum(gram[i][j] * v[j] for j in range(rows))
                     for i in range(rows))
    return math.sqrt(max(0.0, eigenvalue))


def corrected_matrix(raw):
    background = [50.0]
    for _ in range(1, 100):
        background.append(background[-1] + 0.1 * (-0.1 * background[-1]))
    return [[raw[i][j] - background[j] for j in range(100)] for i in range(10)]


def write_csv(matrix):
    with open(RAW_FILE, 'w', newline='') as f:
        csv.writer(f).writerows(matrix)


def run_and_check(raw):
    write_csv(raw)
    if os.path.exists(RESULT_FILE):
        os.remove(RESULT_FILE)

    proc = subprocess.run([BINARY], cwd=PROJECT, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=120)
    assert proc.returncode == 0, \
        f"Built process failed with exit code {proc.returncode}:\n{proc.stderr}"
    assert os.path.isfile(RESULT_FILE), "Running process.go did not create svd_result.txt."

    with open(RESULT_FILE, 'r') as f:
        content = f.read().strip()
    assert re.fullmatch(r'\d+\.\d{4}', content), \
        f"Expected one nonnegative float with exactly 4 decimal places, got '{content}'."

    expected = largest_singular_value(corrected_matrix(raw))
    expected_text = f"{expected:.4f}"
    assert content == expected_text, \
        f"For verifier-supplied input, expected {expected_text}, but program wrote {content}."


def test_build_and_execute_pipeline_on_derived_inputs():
    """Build the submitted Go artifact and exercise ingestion, Euler subtraction, and SVD."""
    build = subprocess.run(['go', 'build', '-o', BINARY, 'process.go'], cwd=PROJECT,
                           text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           timeout=120)
    assert build.returncode == 0, f"process.go did not build successfully:\n{build.stderr}"

    with open(RAW_FILE, 'rb') as f:
        original_raw = f.read()
    original_result = None
    if os.path.isfile(RESULT_FILE):
        with open(RESULT_FILE, 'rb') as f:
            original_result = f.read()

    try:
        case1 = [[17.0 + 0.73 * i + 2.4 * math.sin(0.081 * j + 0.19 * i)
                  + 0.35 * math.cos(0.043 * j * (i + 1))
                  for j in range(100)] for i in range(10)]

        background = [50.0]
        for _ in range(1, 100):
            background.append(background[-1] * 0.99)
        case2 = [[background[j] + (i - 4.5) * math.cos(0.11 * j)
                  + 0.25 * (i + 1) * math.sin(0.037 * j)
                  + 0.02 * ((j % 7) - 3)
                  for j in range(100)] for i in range(10)]

        run_and_check(case1)
        run_and_check(case2)
    finally:
        with open(RAW_FILE, 'wb') as f:
            f.write(original_raw)
        if original_result is None:
            if os.path.exists(RESULT_FILE):
                os.remove(RESULT_FILE)
        else:
            with open(RESULT_FILE, 'wb') as f:
                f.write(original_result)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
