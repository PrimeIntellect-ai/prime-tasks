#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import pytest

MODEL_DIR = "/home/user/model"
SOURCE_PATH = os.path.join(MODEL_DIR, "fit_model.cpp")
EXE_PATH = os.path.join(MODEL_DIR, "fit_model")
VERIFIED_EXE = "/tmp/fit_model_verified"
SIGNALS_PATH = os.path.join(MODEL_DIR, "signals.csv")
FASTA_PATH = os.path.join(MODEL_DIR, "proteins.fasta")


def invert_4x4(A):
    n = 4
    inv = [[1.0 if i == j else 0.0 for j in range(n)] for i in range(n)]
    a = [row[:] for row in A]
    for i in range(n):
        pivot = a[i][i]
        for j in range(n):
            a[i][j] /= pivot
            inv[i][j] /= pivot
        for k in range(n):
            if k != i:
                factor = a[k][i]
                for j in range(n):
                    a[k][j] -= factor * a[i][j]
                    inv[k][j] -= factor * inv[i][j]
    return inv


def weights_for(X, y):
    XtX = [[sum(X[k][i] * X[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
    for i in range(4):
        XtX[i][i] += 0.1
    inv_XtX = invert_4x4(XtX)
    XtY = [sum(X[k][i] * y[k] for k in range(4)) for i in range(4)]
    w = [sum(inv_XtX[i][j] * XtY[j] for j in range(4)) for i in range(4)]
    return " ".join(f"{val:.4f}" for val in w)


def compute_expected_weights():
    X = [
        [1.0, 2.0, 3.0, 4.0],
        [2.0, 4.0, 6.0, 8.001],
        [1.0, 0.0, 1.0, 0.0],
        [0.0, 1.0, 0.0, 1.0]
    ]
    y = [21.0, 16.0, 61.0, 61.0]
    return weights_for(X, y)


def run_model(path):
    result = subprocess.run(
        [path], cwd=MODEL_DIR, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f"{path} failed with exit code {result.returncode}.\n"
        f"stderr: {result.stderr}"
    )
    return result.stdout.strip()


def test_executable_exists():
    exe_path = "/home/user/model/fit_model"
    assert os.path.isfile(exe_path), f"The compiled executable {exe_path} is missing. Did you compile the program?"
    assert os.access(exe_path, os.X_OK), f"The file {exe_path} is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe_path} is not a compiled ELF executable."


def test_weights_output_exists():
    output_path = "/home/user/weights_output.txt"
    assert os.path.isfile(output_path), f"The output file {output_path} is missing. Did you save the output weights?"


def test_weights_output_content():
    output_path = "/home/user/weights_output.txt"
    assert os.path.isfile(output_path), f"The output file {output_path} is missing."

    with open(output_path, "r") as f:
        content = f.read().strip()

    expected_content = compute_expected_weights()

    assert content == expected_content, (
        f"The contents of {output_path} are incorrect.\n"
        f"Expected: '{expected_content}'\n"
        f"Got: '{content}'\n"
        "Ensure you added the ridge penalty lambda = 0.1 to the diagonal of XtX."
    )


def test_submitted_executable_runs_on_original_inputs():
    assert run_model(EXE_PATH) == compute_expected_weights()


def test_source_compiles():
    assert os.path.isfile(SOURCE_PATH), f"The source file {SOURCE_PATH} is missing."
    result = subprocess.run(
        ["g++", "-std=c++11", SOURCE_PATH, "-o", VERIFIED_EXE],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, f"fit_model.cpp does not compile:\n{result.stderr}"
    assert os.path.isfile(VERIFIED_EXE) and os.access(VERIFIED_EXE, os.X_OK)


def test_source_and_executable_on_derived_inputs():
    if not os.path.isfile(VERIFIED_EXE):
        pytest.fail("The verified build was not created.")

    with open(SIGNALS_PATH, "rb") as f:
        original_signals = f.read()
    with open(FASTA_PATH, "rb") as f:
        original_fasta = f.read()

    rng = secrets.SystemRandom()
    try:
        for case_number in range(2):
            X = []
            for i in range(4):
                row = [float(rng.randint(-2, 2)) for _ in range(4)]
                row[i] += float(rng.randint(5, 9))
                X.append(row)
            y = [rng.randint(7, 75) for _ in range(4)]

            with open(SIGNALS_PATH, "w") as f:
                for row in X:
                    f.write(", ".join(str(value) for value in row) + "\n")
            with open(FASTA_PATH, "w") as f:
                for i, length in enumerate(y):
                    f.write(f">generated_{case_number}_{i}\n")
                    f.write("A" * length + "\n")

            expected = weights_for(X, [float(value) for value in y])
            for executable in (EXE_PATH, VERIFIED_EXE):
                actual = run_model(executable)
                assert actual == expected, (
                    f"{executable} produced incorrect weights for derived input.\n"
                    f"Expected: '{expected}'\nGot: '{actual}'\n"
                    "The implementation must add lambda = 0.1 to every diagonal entry of XtX."
                )
    finally:
        with open(SIGNALS_PATH, "wb") as f:
            f.write(original_signals)
        with open(FASTA_PATH, "wb") as f:
            f.write(original_fasta)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
