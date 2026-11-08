#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess

SOURCE = "/home/user/fast_analysis.c"
EXECUTABLE = "/home/user/fast_analysis"
PDB_FILE = "/home/user/data.pdb"
RESULT_FILE = "/home/user/stat_result.txt"


def expected_result(pdb_file):
    n1 = 0
    n2 = 0
    sum_z1 = 0.0
    sum_z2 = 0.0

    with open(pdb_file, "r") as f:
        for line in f:
            if line.startswith("ATOM"):
                x = float(line[30:38].strip())
                z = float(line[46:54].strip())
                if x >= 0:
                    n1 += 1
                    sum_z1 += z
                else:
                    n2 += 1
                    sum_z2 += z

    assert n1 > 0, "No atoms found in Domain 1 (X >= 0.0)"
    assert n2 > 0, "No atoms found in Domain 2 (X < 0.0)"

    mu1 = sum_z1 / n1
    mu2 = sum_z2 / n2
    z_score = (mu1 - mu2) / math.sqrt(1.0 / n1 + 1.0 / n2)
    return f"Z-score: {z_score:.3f}"


def run_program(timeout=5):
    completed = subprocess.run(
        [EXECUTABLE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert completed.returncode == 0, (
        f"fast_analysis exited with status {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )


def test_fast_analysis_c_exists():
    """Test that the C source file exists."""
    assert os.path.isfile(SOURCE), "The file /home/user/fast_analysis.c does not exist."


def test_fast_analysis_executable_exists():
    """Test that the compiled executable exists."""
    assert os.path.isfile(EXECUTABLE), "The compiled executable /home/user/fast_analysis does not exist."
    assert os.access(EXECUTABLE, os.X_OK), "The file /home/user/fast_analysis is not executable."


def test_source_compiles_and_runs():
    """Compile the submitted C source using the required command and execute it."""
    completed = subprocess.run(
        ["gcc", "-O3", SOURCE, "-lm", "-o", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, f"Compilation failed: {completed.stderr}"
    assert os.path.isfile(EXECUTABLE), "Compilation did not create /home/user/fast_analysis."
    assert os.access(EXECUTABLE, os.X_OK), "Compiled /home/user/fast_analysis is not executable."
    run_program()


def test_stat_result():
    """Test that the stat_result.txt contains the correct Z-score."""
    assert os.path.isfile(PDB_FILE), f"Missing required file: {PDB_FILE}"
    assert os.path.isfile(RESULT_FILE), f"The result file {RESULT_FILE} does not exist."

    expected_output = expected_result(PDB_FILE)
    with open(RESULT_FILE, "r") as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, (
        f"Expected '{expected_output}', but got '{actual_output}' in {RESULT_FILE}"
    )


def test_executable_on_fresh_pdb_data():
    """Ensure the compiled submission computes, rather than hard-codes, the answer."""
    with open(PDB_FILE, "rb") as f:
        original_pdb = f.read()
    original_result = None
    if os.path.exists(RESULT_FILE):
        with open(RESULT_FILE, "rb") as f:
            original_result = f.read()

    rng = random.SystemRandom()
    try:
        with open(PDB_FILE, "w") as f:
            for i in range(100000):
                serial = (i % 99999) + 1
                x = rng.uniform(-75.0, 75.0)
                y = rng.uniform(-50.0, 50.0)
                z = rng.uniform(-12.0, 12.0) + (0.8 if x >= 0 else -0.4)
                f.write(
                    f"ATOM  {serial:5d}  CA  ALA A   1    "
                    f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n"
                )

        expected_output = expected_result(PDB_FILE)
        if os.path.exists(RESULT_FILE):
            os.remove(RESULT_FILE)
        run_program()
        assert os.path.isfile(RESULT_FILE), "Program did not create /home/user/stat_result.txt."
        with open(RESULT_FILE, "r") as f:
            actual_output = f.read().strip()
        assert actual_output == expected_output, (
            f"On fresh PDB data, expected '{expected_output}', but got '{actual_output}'"
        )
    finally:
        with open(PDB_FILE, "wb") as f:
            f.write(original_pdb)
        if original_result is None:
            if os.path.exists(RESULT_FILE):
                os.remove(RESULT_FILE)
        else:
            with open(RESULT_FILE, "wb") as f:
                f.write(original_result)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
