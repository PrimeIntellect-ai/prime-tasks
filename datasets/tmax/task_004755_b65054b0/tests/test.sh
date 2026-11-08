#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

RESULTS_PATH = "/home/user/results.txt"
PDB_PATH = "/home/user/protein.pdb"
SOURCE_PATH = "/home/user/simulate.go"
MODULE_PATH = "/home/user/go.mod"


def expected_from_pdb(pdb_path):
    z_coords = []
    with open(pdb_path, "r") as f:
        for line in f:
            if line.startswith("ATOM"):
                z_str = line[46:54].strip()
                z_coords.append(float(z_str))

    assert len(z_coords) > 0, "No ATOM lines found in PDB file."

    z_min = min(z_coords)
    z_max = max(z_coords)
    z_start = math.floor(z_min)
    z_end = math.ceil(z_max)

    cells = []
    dx_min = 1.0
    for i in range(int(z_start), int(z_end)):
        lower = float(i)
        upper = lower + 1.0

        contains_atom = False
        for z in z_coords:
            if lower <= z < upper:
                contains_atom = True
                break
            if upper == z_end and z == upper:
                contains_atom = True
                break

        if contains_atom:
            cells.append((lower, lower + 0.5, 0.5))
            cells.append((lower + 0.5, upper, 0.5))
            dx_min = 0.5
        else:
            cells.append((lower, upper, 1.0))

    midpoint_space = (z_start + z_end) / 2.0
    domain1_cells = 0
    domain2_cells = 0
    integral = 0.0

    for lower, upper, width in cells:
        mid = (lower + upper) / 2.0
        if mid < midpoint_space:
            domain1_cells += 1
        else:
            domain2_cells += 1
        integral += (mid ** 2) * width

    dt = 0.2
    is_stable = dt <= (dx_min ** 2) / 2.0
    stability_str = "STABLE" if is_stable else "UNSTABLE"

    return (
        f"Total Atoms: {len(z_coords)}\n"
        f"Z_min: {z_min:.4f}\n"
        f"Z_max: {z_max:.4f}\n"
        f"Domain 1 Cells: {domain1_cells}\n"
        f"Domain 2 Cells: {domain2_cells}\n"
        f"Integral: {integral:.4f}\n"
        f"Stability dt=0.2: {stability_str}\n"
    )


def assert_results_match(pdb_path=PDB_PATH):
    expected_stripped = expected_from_pdb(pdb_path).strip()
    assert os.path.exists(RESULTS_PATH), f"{RESULTS_PATH} does not exist."
    assert os.path.isfile(RESULTS_PATH), f"{RESULTS_PATH} is not a file."
    with open(RESULTS_PATH, "r") as f:
        actual_output = f.read().strip()
    assert actual_output == expected_stripped, (
        f"Results do not match expected output.\n"
        f"Expected:\n{expected_stripped}\n\nActual:\n{actual_output}"
    )


def make_pdb(z_coords):
    lines = ["HEADER    VERIFIER GENERATED PROTEIN\n"]
    for serial, z in enumerate(z_coords, 1):
        line = (
            f"ATOM  {serial:5d}  CA  GLY A{serial:4d}    "
            f"{0.0:8.3f}{0.0:8.3f}{z:8.3f}  1.00 10.00           C\n"
        )
        assert float(line[46:54].strip()) == float(f"{z:.3f}")
        lines.append(line)
    lines.append("TER\n")
    return "".join(lines)


def run_submission():
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    completed = subprocess.run(
        ["go", "run", "simulate.go"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        "Go program failed.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    assert_results_match()


def test_results_txt_exists():
    assert os.path.exists(RESULTS_PATH), f"{RESULTS_PATH} does not exist."
    assert os.path.isfile(RESULTS_PATH), f"{RESULTS_PATH} is not a file."


def test_results_txt_content():
    assert os.path.exists(PDB_PATH), f"Input file {PDB_PATH} is missing."
    assert_results_match()


def test_go_source_and_module_exist():
    assert os.path.exists(SOURCE_PATH), f"{SOURCE_PATH} does not exist."
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a file."
    assert os.path.exists(MODULE_PATH), f"{MODULE_PATH} does not exist."
    assert os.path.isfile(MODULE_PATH), f"{MODULE_PATH} is not a file."

    completed = subprocess.run(
        ["go", "list", "-m"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        "The Go module is invalid or unusable.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )


def test_go_program_on_unseen_inputs():
    with open(PDB_PATH, "rb") as f:
        original_pdb = f.read()

    base1 = secrets.randbelow(13) - 8
    span1 = secrets.randbelow(5) + 4
    base2 = secrets.randbelow(11) - 5
    span2 = secrets.randbelow(6) + 5

    cases = [
        [-2.000, -1.500, 0.000, 2.000],
        [
            float(base1),
            base1 + 0.125,
            base1 + 1.875,
            base1 + span1 - 0.375,
            float(base1 + span1),
        ],
        [
            float(base2),
            base2 + 0.500,
            base2 + 0.500,
            base2 + 2.250,
            base2 + span2 - 1.125,
            float(base2 + span2),
        ],
    ]

    try:
        for z_coords in cases:
            with open(PDB_PATH, "w") as f:
                f.write(make_pdb(z_coords))
            run_submission()
    finally:
        with open(PDB_PATH, "wb") as f:
            f.write(original_pdb)

    # Run once more on the required input and leave results.txt produced by Go.
    run_submission()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
