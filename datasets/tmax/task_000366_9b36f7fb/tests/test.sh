#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import shutil
import stat
import subprocess

import pytest

EIGEN_DIR = "/home/user/eigen_src"
CPP_PATH = "/home/user/workspace/extract_features.cpp"
EXE_PATH = "/home/user/workspace/ml_feat_prep"
PDB_PATH = "/home/user/data/protein.pdb"
FASTA_PATH = "/home/user/data/sequence.fasta"
CSV_PATH = "/home/user/output/features.csv"


def find_eigen_include():
    for root, dirs, files in os.walk(EIGEN_DIR):
        if os.path.basename(root) == "Eigen" and "Core" in files:
            return os.path.dirname(root)
    return None


def test_eigen_downloaded_and_extracted():
    """Test that Eigen 3.4.0 headers are extracted and usable."""
    assert os.path.isdir(EIGEN_DIR), f"Eigen directory missing: {EIGEN_DIR}"
    include_dir = find_eigen_include()
    assert include_dir is not None, "Could not find Eigen/Core headers in /home/user/eigen_src"

    probe = "/tmp/eigen_probe.cpp"
    probe_exe = "/tmp/eigen_probe"
    with open(probe, "w") as f:
        f.write(r'''#include <Eigen/Core>
#if EIGEN_WORLD_VERSION != 3 || EIGEN_MAJOR_VERSION != 4 || EIGEN_MINOR_VERSION != 0
#error Wrong Eigen version
#endif
int main() { Eigen::Matrix2d m = Eigen::Matrix2d::Identity(); return m(0,0) == 1.0 ? 0 : 1; }
''')
    result = subprocess.run(
        ["g++", "-std=c++17", probe, "-I", include_dir, "-o", probe_exe],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert result.returncode == 0, f"Eigen headers are not usable Eigen 3.4.0 headers:\n{result.stderr}"
    result = subprocess.run([probe_exe], timeout=10)
    assert result.returncode == 0


def test_cpp_code_exists():
    """Test that the C++ source file exists."""
    assert os.path.isfile(CPP_PATH), f"C++ source file missing: {CPP_PATH}"


def test_executable_exists():
    """Test that the compiled executable exists and is executable."""
    assert os.path.isfile(EXE_PATH), f"Executable missing: {EXE_PATH}"
    assert os.access(EXE_PATH, os.X_OK), f"File is not executable: {EXE_PATH}"


def compute_original_ground_truth():
    coords = [
        [11.0, 10.0, 10.0], [13.0, 11.0, 11.0],
        [15.0, 12.0, 12.0], [17.0, 13.0, 13.0],
        [19.0, 14.0, 14.0], [21.0, 15.0, 15.0],
        [23.0, 16.0, 16.0], [25.0, 17.0, 17.0],
        [27.0, 18.0, 18.0], [29.0, 19.0, 19.0]
    ]
    expected_lines = ["56.3323,11.3326,4.4925"]
    for i in range(len(coords)):
        distances = []
        for j in range(len(coords)):
            if i != j:
                d = math.sqrt(sum((coords[i][k] - coords[j][k]) ** 2 for k in range(3)))
                distances.append((d, j))
        distances.sort(key=lambda x: (x[0], x[1]))
        expected_lines.append(f"{i},{distances[0][1]},{distances[1][1]},{distances[2][1]}")
    return expected_lines


def read_nonempty_lines():
    assert os.path.isfile(CSV_PATH), f"Output CSV missing: {CSV_PATH}"
    with open(CSV_PATH, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_output_csv_content():
    """Retain the original final-output assertion."""
    lines = read_nonempty_lines()
    expected_lines = compute_original_ground_truth()
    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in CSV, found {len(lines)}"
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Mismatch on line {i+1}. Expected: '{expected}', Actual: '{actual}'"


def singular_values_of_symmetric(matrix):
    """Independent Jacobi eigensolver; singular values of a real symmetric matrix are |eigenvalues|."""
    a = [row[:] for row in matrix]
    n = len(a)
    for _ in range(200 * n * n):
        p, q = 0, 1
        largest = 0.0
        for i in range(n):
            for j in range(i + 1, n):
                if abs(a[i][j]) > largest:
                    largest = abs(a[i][j])
                    p, q = i, j
        if largest < 1e-12:
            break
        app, aqq, apq = a[p][p], a[q][q], a[p][q]
        angle = 0.5 * math.atan2(2.0 * apq, aqq - app)
        c, s = math.cos(angle), math.sin(angle)
        for k in range(n):
            if k == p or k == q:
                continue
            akp, akq = a[k][p], a[k][q]
            a[k][p] = a[p][k] = c * akp - s * akq
            a[k][q] = a[q][k] = s * akp + c * akq
        a[p][p] = c*c*app - 2.0*s*c*apq + s*s*aqq
        a[q][q] = s*s*app + 2.0*s*c*apq + c*c*aqq
        a[p][q] = a[q][p] = 0.0
    return sorted((abs(a[i][i]) for i in range(n)), reverse=True)


def expected_for(coords):
    n = len(coords)
    dmat = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            dmat[i][j] = math.sqrt(sum((coords[i][k] - coords[j][k]) ** 2 for k in range(3)))
    sv = singular_values_of_symmetric(dmat)[:3]
    lines = [",".join(f"{value:.4f}" for value in sv)]
    for i in range(n):
        ranked = sorted((dmat[i][j], j) for j in range(n) if j != i)
        lines.append(f"{i},{ranked[0][1]},{ranked[1][1]},{ranked[2][1]}")
    return lines


def write_fixture(coords, sequence=None):
    if sequence is None:
        sequence = "A" * len(coords)
    serial = 1
    with open(PDB_PATH, "w") as f:
        for residue, (x, y, z) in enumerate(coords, 1):
            # Include a non-CA ATOM record so the parser must filter atom names.
            f.write(f"ATOM  {serial:5d} {'N':^4s} ALA A{residue:4d}    {x-0.4:8.3f}{y+0.2:8.3f}{z:8.3f}  1.00  0.00           N  \n")
            serial += 1
            f.write(f"ATOM  {serial:5d} {'CA':^4s} ALA A{residue:4d}    {x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n")
            serial += 1
    with open(FASTA_PATH, "w") as f:
        f.write(">dynamic_verifier_fixture\n")
        midpoint = max(1, len(sequence) // 2)
        f.write(sequence[:midpoint] + "\n" + sequence[midpoint:] + "\n")


def run_and_check(executable, coords):
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(
        [executable], cwd="/home/user/workspace",
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"Program failed on a valid altered input (exit {result.returncode}).\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    actual = read_nonempty_lines()
    expected = expected_for(coords)
    assert actual == expected, f"Wrong dynamically computed output.\nExpected: {expected}\nActual: {actual}"


def test_program_executes_on_altered_inputs_and_validates_fasta_length():
    include_dir = find_eigen_include()
    assert include_dir is not None

    backups = {}
    for path in (PDB_PATH, FASTA_PATH, CSV_PATH):
        backups[path] = open(path, "rb").read() if os.path.exists(path) else None

    rebuilt = "/tmp/rebuilt_ml_feat_prep"
    try:
        # Recompile the submitted C++ source, ensuring the source itself is a viable implementation.
        compile_result = subprocess.run(
            ["g++", "-std=c++17", "-O2", CPP_PATH, "-I", include_dir, "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120
        )
        assert compile_result.returncode == 0, f"Submitted C++ source does not compile:\n{compile_result.stderr}"

        coords_a = [
            (0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (-1.0, 0.0, 0.0),
            (0.0, 2.0, 0.0), (0.0, 0.0, 3.0), (4.0, 1.0, 0.0),
            (-2.0, -2.0, 1.0)
        ]
        write_fixture(coords_a, "ACDEFGH")
        run_and_check(EXE_PATH, coords_a)

        coords_b = [
            (2.0, 1.0, 0.0), (2.0, 1.0, 2.0), (5.0, 1.0, 0.0),
            (-1.0, 4.0, 0.0), (0.0, 0.0, -2.0), (7.0, -3.0, 1.0),
            (1.0, 6.0, 3.0), (4.0, 4.0, -1.0)
        ]
        write_fixture(coords_b, "ACDEFGHI")
        run_and_check(rebuilt, coords_b)

        # The demanded executable must reject a FASTA/PDB residue-count mismatch.
        write_fixture(coords_b, "ACDEFGH")
        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)
        mismatch = subprocess.run(
            [EXE_PATH], cwd="/home/user/workspace",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert mismatch.returncode != 0, "Program accepted a FASTA sequence whose length differs from the CA count"
    finally:
        for path, data in backups.items():
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "wb") as f:
                    f.write(data)
        if os.path.exists(rebuilt):
            os.remove(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
