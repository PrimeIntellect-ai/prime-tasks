#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import math
import os
import random
import re
import secrets
import subprocess
import tempfile
import uuid

import pytest

GO_SCRIPT = "/home/user/check_matrix.go"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
BINARY = os.path.join(tempfile.gettempdir(), "check_matrix_" + uuid.uuid4().hex)


def extract_damping():
    result = subprocess.run(
        ["tesseract", "/app/formula.png", "stdout"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, result.stderr
    match = re.search(r"DAMPING\s*=\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)", result.stdout)
    assert match, f"Could not extract DAMPING from OCR output: {result.stdout!r}"
    return float(match.group(1))


DAMPING = extract_damping()


@pytest.fixture(scope="session", autouse=True)
def build_submission():
    assert os.path.isfile(GO_SCRIPT), f"The Go script was not found at {GO_SCRIPT}."
    result = subprocess.run(
        ["go", "build", "-o", BINARY, GO_SCRIPT],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Go source did not build:\n{result.stdout}\n{result.stderr}"
    yield
    try:
        os.remove(BINARY)
    except FileNotFoundError:
        pass


def run_tool(path):
    try:
        return subprocess.run([BINARY, path], capture_output=True, timeout=10).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Submission timed out on {path}")


def reference_accepts(matrix):
    n = len(matrix)
    assert n > 0 and all(len(row) == n for row in matrix)
    a = [row[:] for row in matrix]
    for i in range(n):
        a[i][i] += DAMPING

    lower = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i + 1):
            value = a[i][j]
            for k in range(j):
                value -= lower[i][k] * lower[j][k]
            if i == j:
                if not math.isfinite(value) or value <= 0.0:
                    return False
                lower[i][j] = math.sqrt(value)
            else:
                if lower[j][j] == 0.0:
                    return False
                lower[i][j] = value / lower[j][j]
    return True


def write_matrix(directory, matrix):
    path = os.path.join(directory, uuid.uuid4().hex + ".csv")
    with open(path, "w", newline="") as handle:
        writer = csv.writer(handle)
        for row in matrix:
            # Scientific notation ensures the submission really parses CSV floats.
            writer.writerow([format(value, ".17e") for value in row])
    return path


def test_go_script_exists():
    assert os.path.isfile(GO_SCRIPT), f"The Go script was not found at {GO_SCRIPT}."


def test_adversarial_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.csv"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = [os.path.basename(f) for f in clean_files if run_tool(f) != 0]
    evil_failed = [os.path.basename(f) for f in evil_files if run_tool(f) == 0]

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected instead of accepted): {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed (accepted instead of rejected): {', '.join(evil_failed)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_generated_hidden_matrices_and_exact_damping():
    rng = random.Random(secrets.randbits(128))
    directory = tempfile.mkdtemp(prefix="matrix_inputs_" + uuid.uuid4().hex + "_")
    cases = []

    # These boundary cases require adding the OCR-derived damping value.
    margin = max(abs(DAMPING) * 1e-6, 1e-12)
    cases.append([[-DAMPING + margin]])
    cases.append([[-DAMPING - margin]])

    # Fixed symmetric cases ensure off-diagonal terms affect the decision.
    cases.extend([
        [[1.0, -0.9], [-0.9, 1.0]],
        [[1.0, 2.0], [2.0, 1.0]],
        [[4.0, 1.5, 0.4], [1.5, 1.0, 0.3], [0.4, 0.3, 0.5]],
    ])

    # Hidden positive-definite cases are formed as L*L^T after damping.
    for _ in range(12):
        n = rng.randint(2, 7)
        lower = [[0.0] * n for _ in range(n)]
        for i in range(n):
            for j in range(i + 1):
                lower[i][j] = rng.uniform(-1.5, 1.5) if i != j else rng.uniform(0.08, 2.0)
        matrix = [[sum(lower[i][k] * lower[j][k] for k in range(n)) for j in range(n)] for i in range(n)]
        for i in range(n):
            matrix[i][i] -= DAMPING
        cases.append(matrix)

    # Hidden indefinite cases have positive leading diagonals but fail at a
    # later Cholesky pivot, so checking signs of input diagonal entries is insufficient.
    for _ in range(12):
        n = rng.randint(2, 7)
        diagonal = rng.uniform(0.1, 3.0)
        off_diagonal = diagonal + DAMPING + rng.uniform(0.02, 2.0)
        matrix = [[0.0] * n for _ in range(n)]
        matrix[0][0] = diagonal
        matrix[1][1] = diagonal
        matrix[0][1] = matrix[1][0] = off_diagonal
        for i in range(2, n):
            matrix[i][i] = rng.uniform(0.2, 4.0)
        cases.append(matrix)

    generated = []
    for matrix in cases:
        generated.append((write_matrix(directory, matrix), reference_accepts(matrix)))

    assert any(expected for _, expected in generated)
    assert any(not expected for _, expected in generated)
    rng.shuffle(generated)

    failures = []
    for path, expected in generated:
        actual = run_tool(path) == 0
        if actual != expected:
            failures.append(f"{os.path.basename(path)}: expected {'accept' if expected else 'reject'}")
    assert not failures, "Incorrect results on hidden matrices: " + "; ".join(failures)


def test_rejects_inputs_that_are_not_square_numeric_matrices():
    directory = tempfile.mkdtemp(prefix="invalid_matrix_" + uuid.uuid4().hex + "_")
    contents = [
        "1,2\n3\n",
        "1,not-a-number\n2,3\n",
        "1,2,3\n4,5,6\n",
        "",
    ]
    for text in contents:
        path = os.path.join(directory, uuid.uuid4().hex + ".csv")
        with open(path, "w") as handle:
            handle.write(text)
        assert run_tool(path) != 0, f"Malformed/non-square CSV was accepted: {text!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
