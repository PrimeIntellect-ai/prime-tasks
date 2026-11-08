#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
from pathlib import Path

import pytest

PDB_PATH = Path('/home/user/trajectory.pdb')
FASTA_PATH = Path('/home/user/sequence.fasta')
RESULT_PATH = Path('/home/user/highest_fluctuation.txt')


def compute_expected_result():
    # Read FASTA sequence
    with open(FASTA_PATH, 'r') as f:
        lines = f.read().strip().split('\n')
        seq = "".join(line for line in lines if not line.startswith('>'))

    # Read PDB and extract CA coordinates
    models = []
    current_model = []
    with open(PDB_PATH, 'r') as f:
        for line in f:
            if line.startswith('MODEL'):
                current_model = []
            elif line.startswith('ATOM') and line[12:16].strip() == 'CA':
                res_seq = int(line[22:26].strip())
                x = float(line[30:38].strip())
                y = float(line[38:46].strip())
                z = float(line[46:54].strip())
                current_model.append((res_seq, x, y, z))
            elif line.startswith('ENDMDL'):
                models.append(current_model)

    # Group coordinates by residue sequence number
    res_coords = {}
    for model in models:
        for res_seq, x, y, z in model:
            if res_seq not in res_coords:
                res_coords[res_seq] = []
            res_coords[res_seq].append((x, y, z))

    # Compute RMSF for each CA atom
    max_rmsf = -1.0
    max_res = None
    for res_seq, coords in res_coords.items():
        n = len(coords)
        avg_x = sum(c[0] for c in coords) / n
        avg_y = sum(c[1] for c in coords) / n
        avg_z = sum(c[2] for c in coords) / n
        variance_sum = sum(
            (c[0] - avg_x) ** 2
            + (c[1] - avg_y) ** 2
            + (c[2] - avg_z) ** 2
            for c in coords
        )
        rmsf = math.sqrt(variance_sum / n)
        if rmsf > max_rmsf:
            max_rmsf = rmsf
            max_res = res_seq

    aa = seq[max_res - 1]
    return f"Residue: {max_res} ({aa}), Max_RMSF: {max_rmsf:.3f}"


def test_highest_fluctuation_file_exists():
    """Test that the output file was created at the correct location."""
    assert RESULT_PATH.exists(), f"The file {RESULT_PATH} was not created."
    assert RESULT_PATH.is_file(), f"The path {RESULT_PATH} exists but is not a file."


def test_highest_fluctuation_content():
    """Test that the output file contains the correctly computed result."""
    if not RESULT_PATH.exists():
        pytest.fail(f"Cannot check content because {RESULT_PATH} is missing.")

    expected_content = compute_expected_result()
    actual_content = RESULT_PATH.read_text().strip()
    assert actual_content == expected_content, (
        f"The content of {RESULT_PATH} is incorrect.\n"
        f"Expected: '{expected_content}'\n"
        f"Actual:   '{actual_content}'"
    )


def make_dynamic_fixture(rng, length, model_count, target):
    alphabet = 'ACDEFGHIKLMNPQRSTVWY'
    three_letter = {
        'A': 'ALA', 'C': 'CYS', 'D': 'ASP', 'E': 'GLU', 'F': 'PHE',
        'G': 'GLY', 'H': 'HIS', 'I': 'ILE', 'K': 'LYS', 'L': 'LEU',
        'M': 'MET', 'N': 'ASN', 'P': 'PRO', 'Q': 'GLN', 'R': 'ARG',
        'S': 'SER', 'T': 'THR', 'V': 'VAL', 'W': 'TRP', 'Y': 'TYR'
    }
    sequence = ''.join(rng.choice(alphabet) for _ in range(length))
    amplitude = rng.uniform(0.8, 1.8)
    center = (model_count - 1) / 2.0
    lines = []

    for model in range(model_count):
        lines.append(f"MODEL     {model + 1:4d}\n")
        serial = 1
        # A non-CA atom ensures the script filters by atom name.
        lines.append(
            f"ATOM  {serial:5d}  N   {three_letter[sequence[0]]:3s} A{1:4d}    "
            f"{0.0:8.3f}{0.0:8.3f}{0.0:8.3f}  1.00  0.00           N\n"
        )
        serial += 1
        for residue in range(1, length + 1):
            base = residue * 2.25
            step = model - center
            if residue == target:
                x = base + amplitude * step
                y = base - 0.55 * amplitude * step
                z = base + 0.30 * amplitude * step
            else:
                small = (0.006 + residue * 0.001) * step
                x = base + small
                y = base - small
                z = base + small * 0.5
            lines.append(
                f"ATOM  {serial:5d}  CA  {three_letter[sequence[residue - 1]]:3s} A{residue:4d}    "
                f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C\n"
            )
            serial += 1
        lines.append('ENDMDL\n')

    return f">dynamic_peptide\n{sequence}\n", ''.join(lines)


def test_python_script_executes_and_handles_new_inputs():
    scripts = sorted(
        p for p in Path('/home/user').rglob('*.py')
        if p.is_file() and not p.is_symlink()
    )
    assert scripts, "No Python script was created under /home/user."

    original_pdb = PDB_PATH.read_bytes()
    original_fasta = FASTA_PATH.read_bytes()
    original_result = RESULT_PATH.read_bytes() if RESULT_PATH.exists() else None
    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    cases = []
    for length, model_count in ((6, 4), (8, 5)):
        target = rng.randint(1, length)
        cases.append(make_dynamic_fixture(rng, length, model_count, target))

    failures = []
    working_script = None
    try:
        for script in scripts:
            try:
                for fasta_text, pdb_text in cases:
                    FASTA_PATH.write_text(fasta_text)
                    PDB_PATH.write_text(pdb_text)
                    expected = compute_expected_result()
                    if RESULT_PATH.exists():
                        RESULT_PATH.unlink()

                    completed = subprocess.run(
                        ['python3', str(script)],
                        cwd='/home/user',
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=15,
                        check=False,
                    )
                    assert completed.returncode == 0, (
                        f"exited with status {completed.returncode}: {completed.stderr[-1000:]}"
                    )
                    assert RESULT_PATH.is_file(), "did not create highest_fluctuation.txt"
                    actual = RESULT_PATH.read_text().strip()
                    assert actual == expected, f"expected '{expected}', got '{actual}'"
                working_script = script
                break
            except (AssertionError, subprocess.TimeoutExpired, OSError) as exc:
                failures.append(f"{script}: {exc}")

        assert working_script is not None, (
            "No submitted Python script correctly processed the dynamic trajectories. "
            + " | ".join(failures)
        )
    finally:
        PDB_PATH.write_bytes(original_pdb)
        FASTA_PATH.write_bytes(original_fasta)
        if original_result is None:
            if RESULT_PATH.exists():
                RESULT_PATH.unlink()
        else:
            RESULT_PATH.write_bytes(original_result)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
