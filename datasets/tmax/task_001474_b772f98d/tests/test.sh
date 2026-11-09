#!/bin/bash
set -u
mkdir -p /logs/verifier

run_checks() (
    set -e
    project=/home/user/ml_prep
    tmpdir=$(mktemp -d)
    cp "$project/data.csv" "$tmpdir/data.csv"
    if [ -f "$project/results.json" ]; then
        cp "$project/results.json" "$tmpdir/pre_results.json"
    fi
    cleanup() {
        cp "$tmpdir/data.csv" "$project/data.csv"
        if [ -f "$tmpdir/verified_results.json" ]; then
            cp "$tmpdir/verified_results.json" "$project/results.json"
        elif [ -f "$tmpdir/pre_results.json" ]; then
            cp "$tmpdir/pre_results.json" "$project/results.json"
        else
            rm -f "$project/results.json"
        fi
        rm -rf "$tmpdir"
    }
    trap cleanup EXIT

    python3 - <<'PY'
import os
import re

project = "/home/user/ml_prep"
source_path = os.path.join(project, "src/main.rs")
cargo_path = os.path.join(project, "Cargo.toml")

assert os.path.isfile(source_path) and not os.path.islink(source_path), \
    "src/main.rs must be a regular Rust source file"
assert os.path.isfile(cargo_path), "Cargo.toml is missing"

with open(cargo_path, encoding="utf-8") as f:
    cargo = f.read()
assert re.search(r"(?m)^\s*nalgebra\s*=", cargo), \
    "Cargo.toml must declare nalgebra as a dependency"

with open(source_path, encoding="utf-8") as f:
    source = f.read()

# Remove comments before checking that the required APIs occur in executable source.
code = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
code = re.sub(r"//[^\n]*", " ", code)
assert re.search(r"\bnalgebra\b", code), \
    "src/main.rs must use nalgebra"
assert re.search(r"\.\s*lu\s*\(", code) or re.search(r"\bLU\s*::\s*new\s*\(", code), \
    "src/main.rs must construct an LU decomposition"
assert re.search(r"\.\s*solve\s*\(", code), \
    "src/main.rs must solve the regression system through a decomposition"
PY

    cd "$project"
    cargo build --release --quiet
    test -x "$project/target/release/ml_prep"

    cat <<'TEST_EOF' > "$tmpdir/test_final_state.py"
import os
import json
import csv
import math
import pytest

PROJECT = "/home/user/ml_prep"

def get_mean(X):
    n = len(X)
    cols = len(X[0])
    return [sum(X[i][j] for i in range(n)) / n for j in range(cols)]

def get_cov(X_centered):
    n = len(X_centered)
    cols = len(X_centered[0])
    cov = [[0.0] * cols for _ in range(cols)]
    for i in range(cols):
        for j in range(cols):
            cov[i][j] = sum(X_centered[k][i] * X_centered[k][j] for k in range(n)) / n
    return cov

def cholesky(A):
    L = [[0.0] * 3 for _ in range(3)]
    for i in range(3):
        for j in range(i + 1):
            s = sum(L[i][k] * L[j][k] for k in range(j))
            if i == j:
                L[i][j] = math.sqrt(max(0.0, A[i][i] - s))
            else:
                L[i][j] = (A[i][j] - s) / L[j][j]
    return L

def forward_sub(L, b):
    y = [0.0] * 3
    for i in range(3):
        s = sum(L[i][j] * y[j] for j in range(i))
        y[i] = (b[i] - s) / L[i][i]
    return y

def transpose(A):
    return [[A[j][i] for j in range(len(A))] for i in range(len(A[0]))]

def matmul(A, B):
    m = len(A)
    n = len(A[0])
    p = len(B[0])
    C = [[0.0] * p for _ in range(m)]
    for i in range(m):
        for j in range(p):
            C[i][j] = sum(A[i][k] * B[k][j] for k in range(n))
    return C

def matvec(A, v):
    return [sum(A[i][j] * v[j] for j in range(len(v))) for i in range(len(A))]

def solve_3x3(A, b):
    M = [row[:] + [b[i]] for i, row in enumerate(A)]
    for i in range(3):
        pivot = M[i][i]
        for j in range(i, 4):
            M[i][j] /= pivot
        for k in range(3):
            if k != i:
                factor = M[k][i]
                for j in range(i, 4):
                    M[k][j] -= factor * M[i][j]
    return [M[i][3] for i in range(3)]

def compute_expected_results():
    X, y = [], []
    with open(os.path.join(PROJECT, "data.csv"), newline="") as f:
        for row in csv.reader(f):
            X.append([float(row[0]), float(row[1]), float(row[2])])
            y.append(float(row[3]))
    assert len(X) == 100
    mu = get_mean(X)
    centered = [[X[i][j] - mu[j] for j in range(3)] for i in range(len(X))]
    sigma = get_cov(centered)
    L = cholesky(sigma)
    W = [forward_sub(L, row) for row in centered]
    Wt = transpose(W)
    beta = solve_3x3(matmul(Wt, W), matvec(Wt, y))
    pred = matvec(W, beta)
    mse = sum((y[i] - pred[i]) ** 2 for i in range(len(y))) / len(y)
    return {"mean": mu, "cholesky_lower": L, "regression_coeffs": beta, "mse": mse}

@pytest.fixture(scope="module")
def expected_results():
    return compute_expected_results()

@pytest.fixture(scope="module")
def actual_results():
    path = os.path.join(PROJECT, "results.json")
    assert os.path.isfile(path), f"The results file {path} does not exist."
    with open(path) as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {path} does not contain valid JSON.")

def test_results_keys(actual_results):
    expected_keys = {"mean", "cholesky_lower", "regression_coeffs", "mse"}
    actual_keys = set(actual_results.keys())
    missing = expected_keys - actual_keys
    extra = actual_keys - expected_keys
    assert not missing, f"Missing keys in results.json: {missing}"
    assert not extra, f"Extra keys in results.json: {extra}"

def test_mean_vector(actual_results, expected_results):
    actual = actual_results["mean"]
    expected = expected_results["mean"]
    assert len(actual) == 3, "Mean vector must have exactly 3 elements."
    for i in range(3):
        assert math.isclose(actual[i], expected[i], rel_tol=1e-3, abs_tol=1e-4), \
            f"Mean mismatch at index {i}: expected {expected[i]:.5f}, got {actual[i]:.5f}"

def test_cholesky_lower(actual_results, expected_results):
    actual = actual_results["cholesky_lower"]
    expected = expected_results["cholesky_lower"]
    assert len(actual) == 3, "Cholesky matrix must have exactly 3 rows."
    for i in range(3):
        assert len(actual[i]) == 3, f"Cholesky matrix row {i} must have exactly 3 elements."
        for j in range(3):
            assert math.isclose(actual[i][j], expected[i][j], rel_tol=1e-3, abs_tol=1e-4), \
                f"Cholesky matrix mismatch at ({i}, {j}): expected {expected[i][j]:.5f}, got {actual[i][j]:.5f}"

def test_regression_coeffs(actual_results, expected_results):
    actual = actual_results["regression_coeffs"]
    expected = expected_results["regression_coeffs"]
    assert len(actual) == 3, "Regression coefficients must have exactly 3 elements."
    for i in range(3):
        assert math.isclose(actual[i], expected[i], rel_tol=1e-3, abs_tol=1e-4), \
            f"Regression coefficient mismatch at index {i}: expected {expected[i]:.5f}, got {actual[i]:.5f}"

def test_mse(actual_results, expected_results):
    actual = actual_results["mse"]
    expected = expected_results["mse"]
    assert isinstance(actual, (int, float)), "MSE must be a number."
    assert math.isclose(actual, expected, rel_tol=1e-3, abs_tol=1e-4), \
        f"MSE mismatch: expected {expected:.5f}, got {actual:.5f}"
TEST_EOF

    # The submitted Rust executable must create the result, rather than relying on
    # a precomputed JSON file left by another tool.
    rm -f "$project/results.json"
    timeout 30 "$project/target/release/ml_prep"
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$tmpdir/test_final_state.py" -x --tb=short
    cp "$project/results.json" "$tmpdir/verified_results.json"

    # Exercise the same executable on a second, verifier-generated data set so a
    # hard-coded copy of the original answers cannot pass.
    python3 - <<'PY'
import csv
import math

path = "/home/user/ml_prep/data.csv"
with open(path, "w", newline="") as f:
    out = csv.writer(f)
    for i in range(100):
        a = (i - 49.5) / 17.0
        b = math.sin(i * 0.37) + 0.08 * a
        c = math.cos(i * 0.19) - 0.12 * a + 0.15 * b
        x0 = 4.2 + 1.1 * a + 0.35 * b
        x1 = -1.7 + 0.55 * a + 1.25 * b + 0.20 * c
        x2 = 2.8 - 0.30 * a + 0.45 * b + 1.40 * c
        y = 0.9 * x0 - 1.3 * x1 + 0.65 * x2 + 0.04 * math.sin(i * 1.13)
        out.writerow([f"{x0:.9f}", f"{x1:.9f}", f"{x2:.9f}", f"{y:.9f}"])
PY
    rm -f "$project/results.json"
    timeout 30 "$project/target/release/ml_prep"
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$tmpdir/test_final_state.py" -x --tb=short
)

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
