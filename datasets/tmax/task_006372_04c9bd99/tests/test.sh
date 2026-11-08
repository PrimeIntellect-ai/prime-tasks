#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import subprocess
import pytest

PIPELINE_DIR = "/home/user/pipeline"
CSV_PATH = "/home/user/data/sensors.csv"
RESULTS_PATH = "/home/user/results.json"
BINARY_PATH = "/tmp/submission-pipeline"

CANONICAL_CSV = """id,vibration,temperature,pressure,risk
1,10,20.5,100.0,5.2
2,NaN,22.1,101.2,6.1
3,12,21.0,99.5,5.5
4,15,23.5,102.1,7.0
5,8,19.0,98.0,4.5
6,NaN,19.5,98.5,4.8
7,14,22.8,101.8,6.8
8,9,20.0,99.0,5.0
9,11,21.5,100.5,5.8
10,NaN,20.8,100.2,5.4
"""

INDEPENDENT_CSV = """id,vibration,temperature,pressure,risk
1,3,17.2,93.4,2.8
2,NaN,24.6,105.1,7.7
3,8,19.1,99.8,4.2
4,12,27.3,96.7,8.1
5,5,22.4,108.2,5.9
6,15,18.8,101.3,6.4
7,NaN,25.5,94.6,7.2
8,9,21.7,103.9,5.6
9,18,29.2,110.4,10.3
10,6,16.9,97.5,3.5
11,13,23.8,106.8,7.9
12,NaN,20.3,91.9,4.7
"""

def invert_matrix(M):
    n = len(M)
    A = [row[:] + [1.0 if i == j else 0.0 for j in range(n)] for i, row in enumerate(M)]
    for i in range(n):
        pivot_row = max(range(i, n), key=lambda r: abs(A[r][i]))
        A[i], A[pivot_row] = A[pivot_row], A[i]
        pivot = A[i][i]
        if abs(pivot) < 1e-12:
            raise ValueError("Matrix is singular")
        for j in range(2 * n):
            A[i][j] /= pivot
        for k in range(n):
            if k != i:
                factor = A[k][i]
                for j in range(2 * n):
                    A[k][j] -= factor * A[i][j]
    return [row[n:] for row in A]

def transpose(M):
    return [[M[j][i] for j in range(len(M))] for i in range(len(M[0]))]

def matmul(A, B):
    return [[sum(A[i][k] * B[k][j] for k in range(len(A[0]))) for j in range(len(B[0]))] for i in range(len(A))]

def calculate_expected(csv_text):
    lines = [line for line in csv_text.strip().splitlines() if line.strip()]
    vibration_raw = []
    temperature = []
    pressure = []
    risk = []
    for line in lines[1:]:
        parts = line.split(',')
        vibration_raw.append(parts[1])
        temperature.append(float(parts[2]))
        pressure.append(float(parts[3]))
        risk.append(float(parts[4]))

    valid_vibes = [int(v) for v in vibration_raw if v != "NaN"]
    mean_vibe = sum(valid_vibes) / len(valid_vibes)
    imputed_vibe = math.floor(mean_vibe + 0.5) if mean_vibe >= 0 else math.ceil(mean_vibe - 0.5)
    vibration = [imputed_vibe if v == "NaN" else int(v) for v in vibration_raw]

    X = [[1.0, v, t, p] for v, t, p in zip(vibration, temperature, pressure)]
    y = [[r] for r in risk]
    X_T = transpose(X)
    weights = [w[0] for w in matmul(invert_matrix(matmul(X_T, X)), matmul(X_T, y))]
    y_hat = [sum(X[i][j] * weights[j] for j in range(4)) for i in range(len(X))]
    mean_y_hat = sum(y_hat) / len(y_hat)
    var_y_hat = sum((yi - mean_y_hat) ** 2 for yi in y_hat) / (len(y_hat) - 1)
    se = math.sqrt(var_y_hat) / math.sqrt(len(y_hat))
    return weights, mean_y_hat, mean_y_hat - 1.96 * se, mean_y_hat + 1.96 * se

def write_input(csv_text):
    os.makedirs(os.path.dirname(CSV_PATH), exist_ok=True)
    with open(CSV_PATH, "w") as f:
        f.write(csv_text)

def run_submission(csv_text):
    write_input(csv_text)
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    proc = subprocess.run(
        [BINARY_PATH], cwd=PIPELINE_DIR, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert proc.returncode == 0, f"Go program failed:\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    assert os.path.isfile(RESULTS_PATH), f"Results file {RESULTS_PATH} does not exist after running the Go program."
    with open(RESULTS_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} is not valid JSON.")

def assert_results(results, expected):
    weights, mean_y_hat, ci_lower, ci_upper = expected
    assert "weights" in results, "'weights' key missing in results.json"
    assert "mean_prediction" in results, "'mean_prediction' key missing in results.json"
    assert "ci_lower" in results, "'ci_lower' key missing in results.json"
    assert "ci_upper" in results, "'ci_upper' key missing in results.json"
    res_weights = results["weights"]
    assert len(res_weights) == 4, "Weights array should have exactly 4 elements."
    for i in range(4):
        assert math.isclose(res_weights[i], weights[i], abs_tol=1e-4), \
            f"Weight {i} mismatch. Expected {weights[i]}, got {res_weights[i]}"
    assert math.isclose(results["mean_prediction"], mean_y_hat, abs_tol=1e-4), \
        f"Mean prediction mismatch. Expected {mean_y_hat}, got {results['mean_prediction']}"
    assert math.isclose(results["ci_lower"], ci_lower, abs_tol=1e-4), \
        f"CI lower bound mismatch. Expected {ci_lower}, got {results['ci_lower']}"
    assert math.isclose(results["ci_upper"], ci_upper, abs_tol=1e-4), \
        f"CI upper bound mismatch. Expected {ci_upper}, got {results['ci_upper']}"

@pytest.fixture(scope="session")
def compiled_program():
    assert os.path.isdir(PIPELINE_DIR), f"Pipeline directory {PIPELINE_DIR} is missing."
    assert os.path.isfile(os.path.join(PIPELINE_DIR, "go.mod")), "Go module file /home/user/pipeline/go.mod is missing."
    go_files = [p for p in glob.glob(os.path.join(PIPELINE_DIR, "*.go")) if not p.endswith("_test.go")]
    assert go_files, "No Go source files were found in /home/user/pipeline."
    proc = subprocess.run(
        ["go", "build", "-o", BINARY_PATH, "."], cwd=PIPELINE_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=180
    )
    assert proc.returncode == 0, f"Go program did not compile:\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    assert os.path.isfile(BINARY_PATH), "Go build did not produce an executable."
    return BINARY_PATH

def test_program_on_independent_input(compiled_program):
    results = run_submission(INDEPENDENT_CSV)
    assert_results(results, calculate_expected(INDEPENDENT_CSV))

def test_results_json_exists_and_correct(compiled_program):
    # Restore the supplied fixture before execution so an agent cannot substitute it.
    results = run_submission(CANONICAL_CSV)
    # Restore it again in case the submitted program attempted to mutate its input.
    write_input(CANONICAL_CSV)

    csv_path = "/home/user/data/sensors.csv"
    assert os.path.isfile(csv_path), f"Input file {csv_path} is missing."

    vibration_raw = []
    temperature = []
    pressure = []
    risk = []

    with open(csv_path, 'r') as f:
        header = f.readline()
        for line in f:
            if not line.strip():
                continue
            parts = line.strip().split(',')
            vibration_raw.append(parts[1])
            temperature.append(float(parts[2]))
            pressure.append(float(parts[3]))
            risk.append(float(parts[4]))

    valid_vibes = [int(v) for v in vibration_raw if v != "NaN"]
    mean_vibe = sum(valid_vibes) / len(valid_vibes)
    imputed_vibe = math.floor(mean_vibe + 0.5)
    vibration = [imputed_vibe if v == "NaN" else int(v) for v in vibration_raw]

    X = [[1.0, v, t, p] for v, t, p in zip(vibration, temperature, pressure)]
    y = [[r] for r in risk]
    X_T = transpose(X)
    X_T_X = matmul(X_T, X)
    inv_X_T_X = invert_matrix(X_T_X)
    X_T_y = matmul(X_T, y)
    w_mat = matmul(inv_X_T_X, X_T_y)
    weights = [w[0] for w in w_mat]

    y_hat = [sum(X[i][j] * weights[j] for j in range(4)) for i in range(len(X))]
    mean_y_hat = sum(y_hat) / len(y_hat)
    var_y_hat = sum((yi - mean_y_hat)**2 for yi in y_hat) / (len(y_hat) - 1)
    std_y_hat = math.sqrt(var_y_hat)
    se = std_y_hat / math.sqrt(len(y_hat))
    ci_lower = mean_y_hat - 1.96 * se
    ci_upper = mean_y_hat + 1.96 * se

    results_path = "/home/user/results.json"
    assert os.path.isfile(results_path), f"Results file {results_path} does not exist."

    assert_results(results, (weights, mean_y_hat, ci_lower, ci_upper))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
