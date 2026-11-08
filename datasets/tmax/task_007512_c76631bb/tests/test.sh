#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import csv
import re
import shutil
import subprocess

HOME = "/home/user"
SOURCE = os.path.join(HOME, "prep_data.cpp")
EXECUTABLE = os.path.join(HOME, "prep_data")
CSV_PATH = os.path.join(HOME, "training_features.csv")
EIGEN_DIR = os.path.join(HOME, "eigen", "Eigen")

ORIGINAL_SPECTRA = [
    [0.2, 0.5, 0.3],
    [0.1, 0.6, 0.3],
    [0.4, 0.4, 0.2],
]


def kl_divergence(p, q):
    return sum(p[i] * math.log(p[i] / q[i]) for i in range(len(p)) if p[i] > 0 and q[i] > 0)


def js_divergence(p, q):
    m = [0.5 * (p[i] + q[i]) for i in range(len(p))]
    return 0.5 * kl_divergence(p, m) + 0.5 * kl_divergence(q, m)


def det3x3(m):
    return (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
            m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
            m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))


def inv3x3(m):
    d = det3x3(m)
    inv = [[0.0] * 3 for _ in range(3)]
    inv[0][0] = (m[1][1] * m[2][2] - m[1][2] * m[2][1]) / d
    inv[0][1] = (m[0][2] * m[2][1] - m[0][1] * m[2][2]) / d
    inv[0][2] = (m[0][1] * m[1][2] - m[0][2] * m[1][1]) / d
    inv[1][0] = (m[1][2] * m[2][0] - m[1][0] * m[2][2]) / d
    inv[1][1] = (m[0][0] * m[2][2] - m[0][2] * m[2][0]) / d
    inv[1][2] = (m[0][2] * m[1][0] - m[0][0] * m[1][2]) / d
    inv[2][0] = (m[1][0] * m[2][1] - m[1][1] * m[2][0]) / d
    inv[2][1] = (m[0][1] * m[2][0] - m[0][0] * m[2][1]) / d
    inv[2][2] = (m[0][0] * m[1][1] - m[0][1] * m[1][0]) / d
    return inv


def expected_inverse(spectra):
    n = 3
    adjacency = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i + 1, n):
            weight = math.exp(-js_divergence(spectra[i], spectra[j]))
            adjacency[i][j] = weight
            adjacency[j][i] = weight

    laplacian = [[0.0] * n for _ in range(n)]
    for i in range(n):
        laplacian[i][i] = sum(adjacency[i])
        for j in range(n):
            laplacian[i][j] -= adjacency[i][j]
        laplacian[i][i] += 1e-5
    return inv3x3(laplacian)


def validate_csv(path, spectra):
    assert os.path.isfile(path), f"Output file {path} not found. Did the executable generate it?"
    actual = []
    with open(path, "r", newline="") as f:
        for row in csv.reader(f):
            if row:
                actual.append([float(x) for x in row])

    expected = expected_inverse(spectra)
    assert len(actual) == 3, f"Expected 3 rows in CSV, got {len(actual)}"
    for i in range(3):
        assert len(actual[i]) == 3, f"Expected 3 columns in row {i}, got {len(actual[i])}"
        for j in range(3):
            assert math.isfinite(actual[i][j]), f"Non-finite matrix value at ({i}, {j})"
            assert math.isclose(actual[i][j], expected[i][j], rel_tol=1e-2, abs_tol=1e-2), \
                f"Matrix mismatch at ({i}, {j}): expected approx {expected[i][j]}, got {actual[i][j]}. Did you add 1e-5 * I to L?"


def compile_source(source_path, output_path):
    result = subprocess.run(
        ["g++", "-std=c++11", "-I/home/user/eigen", source_path, "-o", output_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"prep_data.cpp did not compile with Eigen:\n{result.stderr}"


def run_and_validate(executable, workdir, spectra):
    output = os.path.join(workdir, "training_features.csv")
    if os.path.lexists(output):
        os.remove(output)
    result = subprocess.run(
        [executable], cwd=workdir, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert result.returncode == 0, f"Executable failed with code {result.returncode}:\n{result.stderr}"
    validate_csv(output, spectra)


def test_eigen_installed():
    assert os.path.isdir(EIGEN_DIR), f"Eigen directory {EIGEN_DIR} does not exist. Did you download and extract it correctly?"
    dense_header = os.path.join(EIGEN_DIR, "Dense")
    assert os.path.isfile(dense_header), f"Eigen/Dense header not found at {dense_header}. Is the directory structure correct?"


def test_executable_compiled():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} not found. Did you compile the C++ code?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "prep_data is not a compiled ELF executable."


def test_training_features_output():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    run_and_validate(EXECUTABLE, HOME, ORIGINAL_SPECTRA)


def test_modified_source_compiles_and_generalizes():
    build_root = "/tmp/prep_data_verifier_build"
    shutil.rmtree(build_root, ignore_errors=True)
    os.makedirs(build_root)

    fixed_dir = os.path.join(build_root, "fixed")
    os.makedirs(fixed_dir)
    fixed_exe = os.path.join(fixed_dir, "prep_data")
    compile_source(SOURCE, fixed_exe)
    run_and_validate(fixed_exe, fixed_dir, ORIGINAL_SPECTRA)

    with open(SOURCE, "r") as f:
        source_text = f.read()

    variant_spectra = [
        [0.55, 0.25, 0.20],
        [0.15, 0.20, 0.65],
        [0.30, 0.40, 0.30],
    ]
    pattern = re.compile(
        r"(vector\s*<\s*vector\s*<\s*double\s*>\s*>\s+spectra\s*=\s*)\{.*?\}(\s*;)",
        re.DOTALL,
    )
    replacement_body = "{\n        {0.55, 0.25, 0.20},\n        {0.15, 0.20, 0.65},\n        {0.30, 0.40, 0.30}\n    }"
    variant_text, count = pattern.subn(
        lambda match: match.group(1) + replacement_body + match.group(2),
        source_text,
        count=1,
    )
    assert count == 1, "Could not locate the spectra declaration in prep_data.cpp."

    variant_dir = os.path.join(build_root, "variant")
    os.makedirs(variant_dir)
    variant_source = os.path.join(variant_dir, "prep_data.cpp")
    variant_exe = os.path.join(variant_dir, "prep_data")
    with open(variant_source, "w") as f:
        f.write(variant_text)
    compile_source(variant_source, variant_exe)
    run_and_validate(variant_exe, variant_dir, variant_spectra)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
