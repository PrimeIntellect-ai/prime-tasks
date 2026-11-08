#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import random
import subprocess

import pytest

PDB_PATH = "/home/user/protein.pdb"
RESULT_PATH = "/home/user/result.txt"
EXECUTABLE = "/tmp/submission_program"


def derive_expected(pdb_path):
    ca_coords = []
    with open(pdb_path, "r") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 8 and parts[0] == "ATOM" and parts[2] == "CA":
                ca_coords.append([float(parts[5]), float(parts[6]), float(parts[7])])
                if len(ca_coords) == 3:
                    break

    assert len(ca_coords) == 3, "Could not find exactly 3 CA atoms in the PDB file."

    A = ca_coords
    n = 3
    L = [[0.0] * n for _ in range(n)]
    U = [[0.0] * n for _ in range(n)]

    for i in range(n):
        L[i][i] = 1.0
        for k in range(i, n):
            sum_val = sum(L[i][j] * U[j][k] for j in range(i))
            U[i][k] = A[i][k] - sum_val
        for k in range(i + 1, n):
            sum_val = sum(L[k][j] * U[j][i] for j in range(i))
            L[k][i] = (A[k][i] - sum_val) / U[i][i]

    y0 = [1.0, 1.0, 1.0]
    dt = 0.1
    y1 = []
    for i in range(n):
        Ly_i = sum(L[i][j] * y0[j] for j in range(n))
        y1.append(y0[i] + dt * Ly_i)

    return f"{y1[0]:.4f} {y1[1]:.4f} {y1[2]:.4f}"


@pytest.fixture(scope="session", autouse=True)
def compile_submission():
    sources = sorted(
        str(path) for path in pathlib.Path("/home/user").rglob("*.c")
        if path.is_file() and not path.is_symlink()
    )
    assert sources, "No regular C source file was written under /home/user."

    completed = subprocess.run(
        ["gcc", "-std=c11", "-O2", *sources, "-o", EXECUTABLE, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, f"C source did not compile:\n{completed.stderr}"
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK)


def run_submission():
    if os.path.lexists(RESULT_PATH):
        os.remove(RESULT_PATH)
    completed = subprocess.run(
        [EXECUTABLE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"Compiled program exited with status {completed.returncode}:\n{completed.stderr}"
    )
    assert os.path.exists(RESULT_PATH), f"Result file not found: {RESULT_PATH}"


def assert_current_result():
    expected_str = derive_expected(PDB_PATH)
    with open(RESULT_PATH, "r") as f:
        result_content = f.read().strip()
    assert result_content == expected_str, (
        f"Expected '{expected_str}' in {RESULT_PATH}, but got '{result_content}'"
    )


def test_result_file():
    """Verify execution and final result.txt against the derived mathematical solution."""
    assert os.path.exists(PDB_PATH), f"PDB file is missing: {PDB_PATH}"
    run_submission()
    assert_current_result()


def make_random_pdb():
    rng = random.SystemRandom()
    while True:
        values = [[rng.randint(5, 40) + rng.randint(1, 999) / 1000.0,
                   rng.randint(-30, 30) + rng.randint(1, 999) / 1000.0]
                  for _ in range(3)]
        A = [[1.0, *values[0]], [2.0, *values[1]], [3.0, *values[2]]]
        second_pivot = A[1][1] - A[1][0] * A[0][1] / A[0][0]
        if abs(second_pivot) > 0.5:
            break

    lines = []
    serial = 1
    residues = [("ALA", 1), ("CYS", 2), ("ASP", 3)]
    for index, (resname, resseq) in enumerate(residues):
        lines.append(
            f"ATOM {serial:6d} N {resname} A {resseq:3d} 9.125 8.250 7.375 1.00 0.00 N\n"
        )
        serial += 1
        x, y = values[index]
        z = rng.randint(-20, 20) + rng.randint(1, 999) / 1000.0
        lines.append(
            f"ATOM {serial:6d} CA {resname} A {resseq:3d} {x:.3f} {y:.3f} {z:.3f} 1.00 0.00 C\n"
        )
        serial += 1
        lines.append(
            f"ATOM {serial:6d} C {resname} A {resseq:3d} 6.125 5.250 4.375 1.00 0.00 C\n"
        )
        serial += 1
    return "".join(lines)


def test_program_uses_pdb_input():
    with open(PDB_PATH, "r") as f:
        original_pdb = f.read()
    try:
        with open(PDB_PATH, "w") as f:
            f.write(make_random_pdb())
        run_submission()
        assert_current_result()
    finally:
        with open(PDB_PATH, "w") as f:
            f.write(original_pdb)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
