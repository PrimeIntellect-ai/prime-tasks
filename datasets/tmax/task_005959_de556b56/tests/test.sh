#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile

import h5py
import numpy as np

WORKSPACE = "/home/user/workspace"


def expected_ridge(A, b):
    return np.linalg.solve(A.T @ A + np.eye(A.shape[1]), A.T @ b)


def test_generate_compiled():
    exe_path = os.path.join(WORKSPACE, "generate")
    assert os.path.isfile(exe_path), "Executable 'generate' is missing. Did you compile generate.c?"
    assert os.access(exe_path, os.X_OK), "'generate' is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "'generate' is not a compiled executable."

    # Execute the submitted binary in a clean directory and inspect what it creates.
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run([exe_path], cwd=tmp, check=True, timeout=20)
        generated = os.path.join(tmp, "input.h5")
        assert os.path.isfile(generated), "Running 'generate' did not create input.h5."
        with h5py.File(generated, "r") as f:
            assert "A" in f and "b" in f, "Generated input.h5 must contain A and b."
            A = f["A"][:]
            b = f["b"][:]
        expected_A = np.fromfunction(lambda i, j: i + j, (10, 10), dtype=float)
        expected_b = np.arange(10, dtype=float)
        np.testing.assert_array_equal(A, expected_A)
        np.testing.assert_array_equal(b, expected_b)


def test_input_h5_exists():
    input_path = os.path.join(WORKSPACE, "input.h5")
    assert os.path.isfile(input_path), "input.h5 is missing. Did you run the compiled 'generate' executable?"
    with h5py.File(input_path, "r") as f:
        assert "A" in f and "b" in f, "input.h5 must contain datasets A and b."
        A = f["A"][:]
        b = f["b"][:]
    expected_A = np.fromfunction(lambda i, j: i + j, (10, 10), dtype=float)
    expected_b = np.arange(10, dtype=float)
    np.testing.assert_array_equal(A, expected_A)
    np.testing.assert_array_equal(b, expected_b)


def test_optimize_implementation_on_independent_input():
    script = os.path.join(WORKSPACE, "optimize.py")
    assert os.path.isfile(script), "optimize.py is missing."

    # Exercise the submitted implementation on a separate rank-deficient problem.
    # The expected answer is derived here rather than taken from submitted files.
    rows = np.arange(1.0, 8.0)
    A = np.column_stack((rows, 2 * rows, -rows, rows + 1, 3 * rows + 2))
    b = np.array([2.0, -1.0, 4.0, 0.5, 3.0, -2.0, 1.5])
    expected = expected_ridge(A, b)

    with tempfile.TemporaryDirectory() as tmp:
        shutil.copy2(script, os.path.join(tmp, "optimize.py"))
        with h5py.File(os.path.join(tmp, "input.h5"), "w") as f:
            f.create_dataset("A", data=A)
            f.create_dataset("b", data=b)
        subprocess.run(["python3", "optimize.py"], cwd=tmp, check=True, timeout=30)
        solution = os.path.join(tmp, "solution.h5")
        assert os.path.isfile(solution), "optimize.py did not create solution.h5."
        with h5py.File(solution, "r") as f:
            assert "x" in f, "solution.h5 created by optimize.py has no x dataset."
            actual = f["x"][:]
        assert actual.shape == expected.shape
        assert np.all(np.isfinite(actual))
        np.testing.assert_allclose(actual, expected, rtol=1e-7, atol=1e-7)


def test_solution_h5_exists():
    solution_path = os.path.join(WORKSPACE, "solution.h5")
    assert os.path.isfile(solution_path), "solution.h5 is missing. Did you run optimize.py successfully?"
    input_path = os.path.join(WORKSPACE, "input.h5")
    with h5py.File(input_path, "r") as f:
        A = f["A"][:]
        b = f["b"][:]
    with h5py.File(solution_path, "r") as f:
        assert "x" in f, "solution.h5 must contain dataset x."
        actual = f["x"][:]
    expected = expected_ridge(A, b)
    assert actual.shape == expected.shape
    assert np.all(np.isfinite(actual))
    np.testing.assert_allclose(actual, expected, rtol=1e-7, atol=1e-7)


def test_output_txt_content():
    output_path = os.path.join(WORKSPACE, "output.txt")
    assert os.path.isfile(output_path), "output.txt is missing. Did you extract and save the output?"

    # Preserve the original independent standard-library recomputation.
    n = 10
    A = [[float(i + j) for j in range(n)] for i in range(n)]
    b = [[float(i)] for i in range(n)]
    A_T = [[A[j][i] for j in range(n)] for i in range(n)]
    ATA = [[sum(A_T[i][k] * A[k][j] for k in range(n)) for j in range(n)] for i in range(n)]
    for i in range(n):
        ATA[i][i] += 1.0
    ATb = [[sum(A_T[i][k] * b[k][0] for k in range(n))] for i in range(n)]
    AM = [row[:] + [1.0 if i == j else 0.0 for j in range(n)] for i, row in enumerate(ATA)]
    for i in range(n):
        pivot = AM[i][i]
        assert pivot != 0, "Zero pivot encountered during matrix inversion."
        for j in range(2 * n):
            AM[i][j] /= pivot
        for k in range(n):
            if k == i:
                continue
            factor = AM[k][i]
            for j in range(2 * n):
                AM[k][j] -= factor * AM[i][j]
    ATA_inv = [row[n:] for row in AM]
    x = [sum(ATA_inv[i][k] * ATb[k][0] for k in range(n)) for i in range(n)]
    expected_str = " ".join(f"{v:.4f}" for v in x[:3])

    with open(output_path, "r") as f:
        content = f.read().strip()
    assert content == expected_str, f"Content of output.txt is incorrect. Expected '{expected_str}', but got '{content}'."

    # Also ensure output.txt was extracted from the submitted solution artifact.
    with h5py.File(os.path.join(WORKSPACE, "solution.h5"), "r") as f:
        solution_text = " ".join(f"{v:.4f}" for v in f["x"][:3])
    assert content == solution_text, "output.txt does not match the first three values in solution.h5."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
