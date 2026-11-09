#!/bin/bash
set -e
mkdir -p /logs/verifier

cp /home/user/data/interactions.csv /tmp/interactions.csv.original
trap 'cp /tmp/interactions.csv.original /home/user/data/interactions.csv' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import subprocess

PROJECT = "/home/user/rna_dynamics"
MANIFEST = os.path.join(PROJECT, "Cargo.toml")
SOURCE = os.path.join(PROJECT, "src", "main.rs")
DATA = "/home/user/data/interactions.csv"
RESULT = "/home/user/result.txt"


def remove_result():
    if os.path.lexists(RESULT):
        assert os.path.isfile(RESULT) or os.path.islink(RESULT), f"{RESULT} is not a regular output file"
        os.unlink(RESULT)


def run_submission():
    remove_result()
    env = os.environ.copy()
    env["CARGO_NET_OFFLINE"] = "true"
    completed = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", MANIFEST],
        cwd=PROJECT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert completed.returncode == 0, (
        "The Rust project did not compile and run successfully.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def read_result():
    assert os.path.exists(RESULT), f"File {RESULT} does not exist. The analysis pipeline may not have run."
    assert os.path.isfile(RESULT), f"{RESULT} is not a regular file."
    with open(RESULT, "r") as f:
        return f.read().strip()


def write_matrix(matrix):
    with open(DATA, "w") as f:
        for row in matrix:
            f.write(",".join(format(value, ".12g") for value in row) + "\n")


def derivative(a, x):
    return [
        math.tanh(sum(a[i][j] * x[j] for j in range(5))) - 0.1 * x[i]
        for i in range(5)
    ]


def expected_integral(a):
    x = [1.0] * 5
    total = 0.0
    dt = 0.01
    for _ in range(500):
        previous = x[0]
        k1 = derivative(a, x)
        k2 = derivative(a, [x[i] + 0.5 * dt * k1[i] for i in range(5)])
        k3 = derivative(a, [x[i] + 0.5 * dt * k2[i] for i in range(5)])
        k4 = derivative(a, [x[i] + dt * k3[i] for i in range(5)])
        x = [x[i] + dt * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i]) / 6.0 for i in range(5)]
        total += 0.5 * dt * (previous + x[0])
    return total


def assert_dynamic_result(expected):
    content = read_result()
    assert re.fullmatch(r"-?\d+\.\d{4}", content), (
        f"Result '{content}' is not formatted to exactly four decimal places."
    )
    actual = float(content)
    assert abs(actual - expected) <= 0.00015, (
        f"Result {actual:.4f} does not match the independently computed value {expected:.4f}."
    )


def test_complete_rust_pipeline():
    assert os.path.isdir(PROJECT), f"Rust project directory {PROJECT} does not exist."
    assert os.path.isfile(MANIFEST), f"Cargo manifest {MANIFEST} does not exist."
    assert os.path.isfile(SOURCE), f"Rust source file {SOURCE} does not exist."

    env = os.environ.copy()
    env["CARGO_NET_OFFLINE"] = "true"
    metadata_run = subprocess.run(
        ["cargo", "metadata", "--offline", "--no-deps", "--format-version", "1", "--manifest-path", MANIFEST],
        cwd=PROJECT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert metadata_run.returncode == 0, f"Invalid Cargo project: {metadata_run.stderr}"
    metadata = json.loads(metadata_run.stdout)
    assert any(package.get("name") == "rna_dynamics" for package in metadata.get("packages", [])), (
        "The Cargo project must contain a package named rna_dynamics."
    )

    # Execute the submitted Rust pipeline on the original matrix before applying
    # the original verifier's result assertions.
    with open("/tmp/interactions.csv.original", "r") as source, open(DATA, "w") as target:
        target.write(source.read())
    run_submission()

    # Original verifier assertions.
    result_file = "/home/user/result.txt"
    assert os.path.exists(result_file), f"File {result_file} does not exist. The analysis pipeline may not have run."
    assert os.path.isfile(result_file), f"{result_file} is not a regular file."
    with open(result_file, "r") as f:
        content = f.read().strip()
    pattern = r"^10\.970[456]$"
    assert re.match(pattern, content), (
        f"Result '{content}' in {result_file} does not match the expected computed integral. "
        "Expected a value around 10.9705 formatted to exactly 4 decimal places."
    )

    rng = random.SystemRandom()

    # A randomized diagonal matrix with x0 as only the third-largest singular
    # direction. Correct rank-2 truncation therefore removes its interaction.
    diagonal = [
        rng.uniform(0.25, 0.45),
        rng.uniform(0.85, 0.95),
        rng.uniform(0.65, 0.75),
        rng.uniform(0.10, 0.20),
        rng.uniform(0.03, 0.08),
    ]
    matrix = [[diagonal[i] if i == j else 0.0 for j in range(5)] for i in range(5)]
    write_matrix(matrix)
    denoised = [[0.0] * 5 for _ in range(5)]
    denoised[1][1] = diagonal[1]
    denoised[2][2] = diagonal[2]
    run_submission()
    assert_dynamic_result(expected_integral(denoised))

    # A randomized dense matrix constructed with rank at most two. Its top-2 SVD
    # reconstruction must preserve the matrix, exercising parsing, matrix-vector
    # dynamics, RK4, and trapezoidal integration on an unseen input.
    while True:
        u = [rng.randint(-3, 3) for _ in range(5)]
        v = [rng.randint(-3, 3) for _ in range(5)]
        p = [rng.randint(-3, 3) for _ in range(5)]
        q = [rng.randint(-3, 3) for _ in range(5)]
        matrix = [[0.04 * (u[i] * v[j] + p[i] * q[j]) for j in range(5)] for i in range(5)]
        if any(abs(matrix[0][j]) > 0.01 for j in range(5)):
            break
    write_matrix(matrix)
    # Re-read the decimal values actually supplied to the program.
    with open(DATA, "r") as f:
        supplied = [[float(value) for value in line.strip().split(",")] for line in f if line.strip()]
    run_submission()
    assert_dynamic_result(expected_integral(supplied))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
