#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess

import numpy as np

NOTEBOOK_PATH = "/home/user/analyze_structure.ipynb"
OUTPUT_PATH = "/home/user/singular_values.txt"
PDB_PATH = "/home/user/protein.pdb"


def derive_expected_values():
    coordinates = []
    with open(PDB_PATH, "r") as pdb_file:
        for line in pdb_file:
            if line.startswith("ATOM") and line[12:16] == " CA ":
                coordinates.append([
                    float(line[30:38]),
                    float(line[38:46]),
                    float(line[46:54]),
                ])

    assert coordinates, "No alpha-carbon coordinates were found in protein.pdb."
    matrix = np.asarray(coordinates, dtype=float)
    centered = matrix - matrix.mean(axis=0)
    singular_values = np.linalg.svd(centered, compute_uv=False)
    return [f"{value:.4f}" for value in singular_values]


# Derive the oracle before executing untrusted notebook code.
EXPECTED_VALUES = derive_expected_values()


def test_notebook_exists():
    assert os.path.exists(NOTEBOOK_PATH), f"The Jupyter notebook {NOTEBOOK_PATH} does not exist."
    assert os.path.isfile(NOTEBOOK_PATH), f"{NOTEBOOK_PATH} is not a file."


def test_notebook_executes_and_generates_output():
    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    output_dir = "/tmp/verifier-executed-notebook"
    shutil.rmtree(output_dir, ignore_errors=True)
    os.mkdir(output_dir)
    os.chmod(output_dir, 0o777)

    jupyter = shutil.which("jupyter")
    assert jupyter is not None, "The jupyter executable is unavailable."

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    result = subprocess.run(
        [
            "runuser", "-u", "user", "--",
            jupyter, "nbconvert",
            "--execute",
            "--to", "notebook",
            "--output", "executed.ipynb",
            "--output-dir", output_dir,
            "--ExecutePreprocessor.timeout=120",
            NOTEBOOK_PATH,
        ],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=150,
    )
    assert result.returncode == 0, "Notebook execution failed:\n" + result.stdout


def test_singular_values_file_exists():
    assert os.path.exists(OUTPUT_PATH), f"The output file {OUTPUT_PATH} does not exist."
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file."


def test_singular_values_contents():
    assert os.path.exists(OUTPUT_PATH), f"The output file {OUTPUT_PATH} does not exist."

    with open(OUTPUT_PATH, "r") as output_file:
        lines = [line.strip() for line in output_file if line.strip()]

    assert len(lines) == 3, f"Expected 3 singular values, but found {len(lines)}."
    assert all(re.fullmatch(r"\d+\.\d{4}", line) for line in lines), \
        "Each singular value must be written with exactly four decimal places."

    for i, (actual, expected) in enumerate(zip(lines, EXPECTED_VALUES)):
        assert actual == expected, f"Line {i+1} mismatch: expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
