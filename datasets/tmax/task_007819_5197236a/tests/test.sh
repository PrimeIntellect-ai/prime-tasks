#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import tempfile

RESULTS = "/home/user/results.txt"
SOURCE = "/home/user/fit_plane.cpp"
BINARY = "/home/user/fit_plane"
STRUCTURE = "/home/user/structure.pdb"


def test_results_file_exists():
    """Test that the results.txt file was created."""
    assert os.path.isfile(RESULTS), f"The file {RESULTS} does not exist. Did you run the compiled executable and redirect standard output to it?"


def test_results_content():
    """Test that results.txt contains the correct regularized fitted values."""
    with open(RESULTS, "r") as f:
        content = f.read().strip()

    expected_domain1 = r"Domain 1:\s*a=0\.7353,\s*b=0\.7647,\s*c=-0\.1471"
    expected_domain2 = r"Domain 2:\s*a=0\.9655,\s*b=0\.9655,\s*c=0\.4138"

    assert re.search(expected_domain1, content), f"Domain 1 results are incorrect or missing in results.txt.\nExpected to match: {expected_domain1}\nActual content:\n{content}"
    assert re.search(expected_domain2, content), f"Domain 2 results are incorrect or missing in results.txt.\nExpected to match: {expected_domain2}\nActual content:\n{content}"


def test_cpp_code_modified():
    """Check that the C++ code was actually modified to add the L2 penalty."""
    assert os.path.isfile(SOURCE), f"The file {SOURCE} is missing."
    with open(SOURCE, "r") as f:
        content = f.read()

    assert re.search(r"XtX\[0\]\[0\]\s*\+=\s*1", content) or re.search(r"XtX\[i\]\[i\]\s*\+=\s*1", content) or re.search(r"XtX\[1\]\[1\]\s*\+=\s*1", content) or "1.0" in content, \
        "Could not find evidence of Ridge Regression (adding 1.0 to the diagonal of XtX) in fit_plane.cpp."


def solve3(matrix, rhs):
    a = [list(map(float, row)) + [float(rhs[i])] for i, row in enumerate(matrix)]
    for col in range(3):
        pivot = max(range(col, 3), key=lambda r: abs(a[r][col]))
        assert abs(a[pivot][col]) > 1e-12
        a[col], a[pivot] = a[pivot], a[col]
        divisor = a[col][col]
        for j in range(col, 4):
            a[col][j] /= divisor
        for row in range(3):
            if row == col:
                continue
            factor = a[row][col]
            for j in range(col, 4):
                a[row][j] -= factor * a[col][j]
    return [a[i][3] for i in range(3)]


def ridge_expected(points):
    xtx = [[0.0] * 3 for _ in range(3)]
    xtz = [0.0] * 3
    for x, y, z in points:
        row = (x, y, 1.0)
        for i in range(3):
            xtz[i] += row[i] * z
            for j in range(3):
                xtx[i][j] += row[i] * row[j]
    for i in range(3):
        xtx[i][i] += 1.0
    return solve3(xtx, xtz)


def pdb_bytes(points):
    lines = []
    for serial, (x, y, z) in enumerate(points, 1):
        lines.append(
            f"ATOM  {serial:5d}  CA  ALA A{serial:4d}    "
            f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n"
        )
    return "".join(lines).encode()


def parse_output(output):
    pattern = re.compile(
        r"^Domain 1: a=(-?\d+\.\d{4}), b=(-?\d+\.\d{4}), c=(-?\d+\.\d{4})\n"
        r"Domain 2: a=(-?\d+\.\d{4}), b=(-?\d+\.\d{4}), c=(-?\d+\.\d{4})\n?$"
    )
    match = pattern.fullmatch(output)
    assert match, f"Unexpected program output format:\n{output}"
    values = list(map(float, match.groups()))
    assert all(math.isfinite(v) for v in values)
    return values[:3], values[3:]


def assert_correct(output, domains):
    actual = parse_output(output)
    expected = tuple(ridge_expected(domain) for domain in domains)
    for domain_id in range(2):
        for coefficient_id in range(3):
            got = actual[domain_id][coefficient_id]
            want = expected[domain_id][coefficient_id]
            assert abs(got - want) <= 5.1e-4, (
                f"Incorrect ridge coefficient for domain {domain_id + 1}: "
                f"got {got}, expected {want:.8f}"
            )


def test_compiled_program_and_source_implement_ridge():
    assert os.path.isfile(BINARY), f"The compiled executable {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."

    with open(RESULTS, "r") as f:
        saved_results = f.read().strip()
    original_run = subprocess.run([BINARY], text=True, capture_output=True, timeout=10)
    assert original_run.returncode == 0, original_run.stderr
    assert original_run.stdout.strip() == saved_results, \
        "results.txt is not the output produced by the submitted executable on structure.pdb."

    fd, rebuilt = tempfile.mkstemp(prefix="fit_plane_rebuilt_", dir="/tmp")
    os.close(fd)
    os.unlink(rebuilt)
    compile_result = subprocess.run(
        ["g++", "-O2", SOURCE, "-o", rebuilt], text=True, capture_output=True, timeout=30
    )
    assert compile_result.returncode == 0, f"Modified source does not compile:\n{compile_result.stderr}"

    with open(STRUCTURE, "rb") as f:
        original_structure = f.read()

    # Runtime-generated offsets prevent a submission from passing by printing the
    # two known answers. Coordinates are rounded exactly as they are stored in PDB.
    shift = secrets.randbelow(601) / 100.0 - 3.0
    d1 = [
        (-1.250, -2.000, 3.125 + shift),
        (-2.500, 0.750, -1.375 + shift),
        (-3.750, 2.250, 4.625 - shift),
        (-0.500, 3.500, -2.250 + shift),
        (-4.250, -1.500, 0.875 - shift),
    ]
    # This domain is deliberately collinear in x/y, reproducing the singular OLS case.
    d2 = [
        (0.500, 1.000, 2.250 + shift),
        (1.500, 3.000, -0.750 - shift),
        (2.500, 5.000, 5.500 + shift),
        (3.500, 7.000, 1.125 - shift),
        (4.500, 9.000, 7.750 + shift),
    ]
    # Match the precision actually parsed from the generated PDB.
    domains = [[tuple(round(v, 3) for v in p) for p in domain] for domain in (d1, d2)]

    try:
        with open(STRUCTURE, "wb") as f:
            f.write(pdb_bytes(domains[0] + domains[1]))
        for executable in (BINARY, rebuilt):
            run = subprocess.run([executable], text=True, capture_output=True, timeout=10)
            assert run.returncode == 0, run.stderr
            assert_correct(run.stdout, domains)
    finally:
        with open(STRUCTURE, "wb") as f:
            f.write(original_structure)
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
