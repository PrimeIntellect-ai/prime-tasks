#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile

EXECUTABLE = "/home/user/analyze_pca"
SOURCE = "/home/user/analyze_pca.cpp"
RESULT = "/home/user/result.txt"
MUTANT = "/home/user/mutant.pdb"


def run_program(executable, pdb_path):
    completed = subprocess.run(
        [executable, pdb_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=False,
    )
    assert completed.returncode == 0, (
        f"{executable} failed on {pdb_path} with exit code {completed.returncode}: "
        f"{completed.stderr}"
    )
    return completed.stdout.strip()


def write_pdb(path, points):
    with open(path, "w") as f:
        for serial, (x, y, z) in enumerate(points, 1):
            # Keep the atom name and coordinates in the fixed columns parsed by the program.
            f.write(
                "ATOM  " + f"{serial:5d}" + " " + " CA " + " " + "GLY" + " " +
                "A" + f"{serial:4d}" + " " + "   " +
                f"{x:8.3f}{y:8.3f}{z:8.3f}" +
                "  1.00  0.00           C  \n"
            )


def expected_trace(points):
    n = len(points)
    means = [sum(p[i] for p in points) / n for i in range(3)]
    cov = [[0.0] * 3 for _ in range(3)]
    for p in points:
        d = [p[i] - means[i] for i in range(3)]
        for i in range(3):
            for j in range(3):
                cov[i][j] += d[i] * d[j]

    # Required Tikhonov regularization on every diagonal element.
    for i in range(3):
        cov[i][i] += 0.0001

    det = (
        cov[0][0] * (cov[1][1] * cov[2][2] - cov[1][2] * cov[2][1])
        - cov[0][1] * (cov[1][0] * cov[2][2] - cov[1][2] * cov[2][0])
        + cov[0][2] * (cov[1][0] * cov[2][1] - cov[1][1] * cov[2][0])
    )
    inv00 = (cov[1][1] * cov[2][2] - cov[1][2] * cov[2][1]) / det
    inv11 = (cov[0][0] * cov[2][2] - cov[0][2] * cov[2][0]) / det
    inv22 = (cov[0][0] * cov[1][1] - cov[0][1] * cov[1][0]) / det
    return f"{inv00 + inv11 + inv22:.2f}"


def exercise(executable):
    rng = random.SystemRandom()
    probes = []

    # Tiny collinear spreads along each axis make omission of any one of the
    # three diagonal additions produce a singular or observably wrong result.
    for axis in range(3):
        step = rng.randint(1, 9) / 1000.0
        offset = [rng.randint(-20, 20) / 1000.0 for _ in range(3)]
        points = []
        for k in range(5):
            p = list(offset)
            p[axis] += k * step
            points.append(tuple(p))
        probes.append(points)

    # Also test a non-collinear covariance matrix using values chosen only at
    # verification time.
    probes.append([
        tuple(rng.randint(-30, 30) / 1000.0 for _ in range(3))
        for _ in range(9)
    ])

    with tempfile.TemporaryDirectory(prefix="pca_verify_") as td:
        for index, points in enumerate(probes):
            pdb_path = os.path.join(td, f"probe_{index}_{rng.randrange(1 << 30)}.pdb")
            write_pdb(pdb_path, points)
            actual = run_program(executable, pdb_path)
            expected = expected_trace(points)
            assert actual == expected, (
                f"{executable} produced '{actual}' for a generated covariance probe; "
                f"expected '{expected}' after adding exactly 0.0001 to all three diagonals."
            )


def test_executable_exists():
    executable_path = EXECUTABLE
    assert os.path.isfile(executable_path), f"The compiled executable {executable_path} does not exist."
    assert os.access(executable_path, os.X_OK), f"The file {executable_path} is not executable."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable_path} is not a compiled ELF executable."


def test_result_file_exists_and_correct():
    result_path = RESULT
    assert os.path.isfile(result_path), f"The result file {result_path} does not exist."

    with open(result_path, "r") as f:
        content = f.read().strip()

    assert content == "20000.10", f"The result file {result_path} contains '{content}', but expected '20000.10'. Ensure that exactly 0.0001 was added to the diagonal elements of the covariance matrix."


def test_cpp_code_modified():
    cpp_path = SOURCE
    assert os.path.isfile(cpp_path), f"The source file {cpp_path} does not exist."

    with open(cpp_path, "r") as f:
        content = f.read()

    # Preserve the original source-level assertion.
    has_regularization = "0.0001" in content or "1e-4" in content or "1E-4" in content
    assert has_regularization, "The source code does not seem to contain the regularization constant 0.0001 (or 1e-4)."


def test_saved_result_is_actual_program_output():
    actual = run_program(EXECUTABLE, MUTANT)
    with open(RESULT, "r") as f:
        saved = f.read().strip()
    assert actual == "20000.10", (
        f"Running {EXECUTABLE} on {MUTANT} produced '{actual}', expected '20000.10'."
    )
    assert saved == actual, "result.txt is not the standard output produced by analyze_pca on mutant.pdb."


def test_installed_executable_regularizes_all_diagonals():
    exercise(EXECUTABLE)


def test_modified_source_builds_and_regularizes_all_diagonals():
    rebuilt = "/tmp/analyze_pca_rebuilt"
    completed = subprocess.run(
        ["g++", "-std=c++11", "-O2", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )
    assert completed.returncode == 0, f"The modified source does not compile: {completed.stderr}"
    exercise(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
