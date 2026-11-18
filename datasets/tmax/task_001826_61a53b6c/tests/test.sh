#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import math
import pytest

EXE = "/home/user/bin/ca_centroid"
PDB_DIR = "/home/user/data/pdbs"
OUTPUT = "/home/user/results/mode_output.txt"


def parse_expected_distance(path):
    coords = []
    with open(path, "r") as f:
        for line in f:
            if line.startswith("ATOM  "):
                atom_name = line[12:16]
                if "CA" in atom_name:
                    coords.append((float(line[30:38]), float(line[38:46]), float(line[46:54])))
    if not coords:
        return 0.0
    n = len(coords)
    cx = sum(p[0] for p in coords) / n
    cy = sum(p[1] for p in coords) / n
    cz = sum(p[2] for p in coords) / n
    return sum(math.sqrt((x-cx)**2 + (y-cy)**2 + (z-cz)**2) for x, y, z in coords) / n


def run_tool(path):
    result = subprocess.run([EXE, path], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"ca_centroid failed on {path}: {result.stderr}"
    text = result.stdout.strip()
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", text), \
        f"ca_centroid did not print one floating-point number: {result.stdout!r}"
    return float(text)


def test_executable_exists():
    assert os.path.isfile(EXE), f"Executable not found at {EXE}"
    assert os.access(EXE, os.X_OK), f"File at {EXE} is not executable"


def test_compiled_executable_behavior():
    # Exercise the required artifact itself, including independently-created inputs
    # that cannot be handled by hard-coding the shipped data set's answers.
    cases = {
        "case1.pdb": [
            "ATOM      1  CA  ALA A   1       0.000   0.000   0.000  1.00  0.00           C  \n",
            "ATOM      2  CA  ALA A   2       2.000   0.000   0.000  1.00  0.00           C  \n",
            "ATOM      3  N   ALA A   3     999.000 999.000 999.000  1.00  0.00           N  \n",
        ],
        "case2.pdb": [
            "ATOM      1  CA  GLY A   1      -3.250   1.500   7.000  1.00  0.00           C  \n",
            "ATOM      2  CA  GLY A   2       4.750  -2.500   1.000  1.00  0.00           C  \n",
            "ATOM      3  CA  GLY A   3       1.250   8.500  -5.000  1.00  0.00           C  \n",
            "HETATM    4  CA  CA  A   4      90.000  90.000  90.000  1.00  0.00          CA  \n",
        ],
        "empty.pdb": ["REMARK no alpha carbons\n"],
    }
    os.makedirs("/tmp/centroid_cases", exist_ok=True)
    for name, lines in cases.items():
        path = os.path.join("/tmp/centroid_cases", name)
        with open(path, "w") as f:
            f.writelines(lines)
        actual = run_tool(path)
        expected = parse_expected_distance(path)
        assert math.isclose(actual, expected, rel_tol=0, abs_tol=1e-5), \
            f"Wrong centroid distance for {name}: expected {expected}, got {actual}"


def test_mode_output_exists_and_format():
    assert os.path.isfile(OUTPUT), f"Output file not found at {OUTPUT}"
    with open(OUTPUT, "r") as f:
        content = f.read()
    assert re.fullmatch(r"-?\d+\.\d{4},-?\d+\.\d{4}\n?", content), \
        f"Output must be exactly one line with two values having exactly four decimal places, got: {content!r}"


def test_correct_mode_and_density():
    # Derive the data by running the required executable, not agent-writable source.
    pdbs = sorted(f for f in os.listdir(PDB_DIR) if f.endswith(".pdb"))
    assert pdbs, "No PDB files found"
    distances = []
    for p in pdbs:
        path = os.path.join(PDB_DIR, p)
        actual = run_tool(path)
        expected = parse_expected_distance(path)
        assert math.isclose(actual, expected, rel_tol=0, abs_tol=1e-5), \
            f"ca_centroid produced an incorrect value for {p}: expected {expected}, got {actual}"
        distances.append(actual)

    script = r'''
import sys
import numpy as np
from scipy.stats import gaussian_kde
from scipy.optimize import minimize
values = np.array([float(v) for v in sys.argv[1:]])
kde = gaussian_kde(values)
def neg_kde(x):
    return -kde(x)[0]
res = minimize(neg_kde, x0=[np.mean(values)], bounds=[(0.0, 100.0)])
if not res.success:
    raise RuntimeError(res.message)
print(f"{res.x[0]:.4f},{(-res.fun):.4f}")
'''
    result = subprocess.run(["python3", "-c", script] + [repr(x) for x in distances],
                            capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Failed to compute expected values: {result.stderr}"
    expected_dist, expected_dens = map(float, result.stdout.strip().split(","))

    with open(OUTPUT, "r") as f:
        student_dist, student_dens = map(float, f.read().strip().split(","))
    assert math.isclose(student_dist, expected_dist, rel_tol=0, abs_tol=1e-3), \
        f"Expected distance ~{expected_dist:.4f}, but got {student_dist:.4f}"
    assert math.isclose(student_dens, expected_dens, rel_tol=0, abs_tol=1e-3), \
        f"Expected density ~{expected_dens:.4f}, but got {student_dens:.4f}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
