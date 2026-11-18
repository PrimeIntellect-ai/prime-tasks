#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess

import numpy as np
import pytest

PROJECT = "/home/user/svd_profile"
MANIFEST = os.path.join(PROJECT, "Cargo.toml")
SOURCE = os.path.join(PROJECT, "src/main.rs")
MATRICES = "/home/user/matrices.json"
RESULTS = "/home/user/svd_results.txt"


def cargo_env():
    env = os.environ.copy()
    user_cargo_home = "/home/user/.cargo"
    if os.path.isdir(user_cargo_home):
        env["CARGO_HOME"] = user_cargo_home
        env["HOME"] = "/home/user"
    return env


def run_cargo():
    proc = subprocess.run(
        ["cargo", "run", "--quiet", "--offline", "--manifest-path", MANIFEST],
        cwd=PROJECT,
        env=cargo_env(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=240,
    )
    assert proc.returncode == 0, "Rust program failed to build or run:\n" + proc.stdout


def read_exact_result():
    assert os.path.isfile(RESULTS), f"Expected result file {RESULTS} does not exist."
    with open(RESULTS, "r") as f:
        content = f.read().strip()
    assert re.fullmatch(r"[+-]?\d+\.\d{4},[+-]?\d+\.\d{4}", content), \
        f"File content '{content}' does not match exact format 'mean,std' with 4 decimal places."
    return content


def largest_singular_value(mat):
    n = len(mat)
    m = len(mat[0])

    # Compute A^T * A
    AtA = [[0.0] * m for _ in range(m)]
    for i in range(m):
        for j in range(m):
            AtA[i][j] = sum(mat[k][i] * mat[k][j] for k in range(n))

    # Power iteration to find the largest eigenvalue of A^T * A
    v = [1.0] * m
    for _ in range(200):
        v_new = [sum(AtA[i][j] * v[j] for j in range(m)) for i in range(m)]
        norm = math.sqrt(sum(x * x for x in v_new))
        if norm == 0:
            break
        v = [x / norm for x in v_new]

    # Rayleigh quotient
    Av = [sum(AtA[i][j] * v[j] for j in range(m)) for i in range(m)]
    lambda_max = sum(v[i] * Av[i] for i in range(m))

    return math.sqrt(lambda_max)


def test_rust_project_exists():
    assert os.path.isdir(PROJECT), "Rust project directory /home/user/svd_profile does not exist."
    assert os.path.isfile(MANIFEST), "Cargo.toml not found in /home/user/svd_profile."
    assert os.path.isfile(SOURCE), "src/main.rs not found in /home/user/svd_profile."

    proc = subprocess.run(
        ["cargo", "metadata", "--offline", "--no-deps", "--format-version", "1", "--manifest-path", MANIFEST],
        cwd=PROJECT,
        env=cargo_env(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert proc.returncode == 0, "Cargo.toml is not a valid Cargo manifest:\n" + proc.stderr
    metadata = json.loads(proc.stdout)
    manifest_real = os.path.realpath(MANIFEST)
    roots = [p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == manifest_real]
    assert roots, "Could not identify the submitted Rust package."
    assert any(dep["name"] == "nalgebra" for dep in roots[0]["dependencies"]), \
        "Cargo.toml must declare nalgebra as a dependency."


def test_rust_program_is_executed_and_handles_unseen_matrices():
    assert os.path.isfile(MATRICES), f"Matrices file {MATRICES} is missing."
    with open(MATRICES, "rb") as f:
        original_matrices = f.read()

    # Use a fresh, dense set of 50 matrices so a precomputed original answer or
    # placeholder Rust project cannot pass. The expected answer is derived here.
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
    probe = rng.normal(0.0, 2.0, size=(50, 10, 10))
    probe += np.eye(10)[None, :, :] * rng.uniform(1.0, 12.0, size=(50, 1, 1))
    maxima = [float(np.linalg.svd(mat, compute_uv=False)[0]) for mat in probe]
    expected_mean = sum(maxima) / len(maxima)
    expected_std = math.sqrt(sum((x - expected_mean) ** 2 for x in maxima) / len(maxima))
    expected = f"{expected_mean:.4f},{expected_std:.4f}"

    try:
        with open(MATRICES, "w") as f:
            json.dump(probe.tolist(), f)
        if os.path.exists(RESULTS):
            os.remove(RESULTS)
        run_cargo()
        actual = read_exact_result()
        assert actual == expected, f"For verifier-generated matrices, expected {expected}, got {actual}."
    finally:
        with open(MATRICES, "wb") as f:
            f.write(original_matrices)
        if os.path.exists(RESULTS):
            os.remove(RESULTS)
        # Regenerate the required final artifact from the original input.
        run_cargo()


def test_svd_results():
    results_file = "/home/user/svd_results.txt"
    matrices_file = "/home/user/matrices.json"

    assert os.path.isfile(results_file), f"Expected result file {results_file} does not exist."
    assert os.path.isfile(matrices_file), f"Matrices file {matrices_file} is missing."

    with open(matrices_file, "r") as f:
        matrices = json.load(f)

    s_maxes = [largest_singular_value(mat) for mat in matrices]

    mean_val = sum(s_maxes) / len(s_maxes)
    std_val = math.sqrt(sum((x - mean_val) ** 2 for x in s_maxes) / len(s_maxes))

    with open(results_file, "r") as f:
        content = f.read().strip()

    parts = content.split(",")
    assert len(parts) == 2, f"File content '{content}' does not match format 'mean,std'."

    try:
        actual_mean = float(parts[0])
        actual_std = float(parts[1])
    except ValueError:
        pytest.fail(f"Could not parse mean and std as floats from '{content}'.")

    # Check format exactly 4 decimal places
    assert "." in parts[0] and len(parts[0].split(".")[1]) == 4, "Mean is not rounded to exactly 4 decimal places."
    assert "." in parts[1] and len(parts[1].split(".")[1]) == 4, "Std is not rounded to exactly 4 decimal places."

    assert math.isclose(actual_mean, mean_val, abs_tol=0.0002), f"Expected mean approx {mean_val:.4f}, got {actual_mean}"
    assert math.isclose(actual_std, std_val, abs_tol=0.0002), f"Expected std approx {std_val:.4f}, got {actual_std}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
