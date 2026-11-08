#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
from pathlib import Path

import numpy as np

WORKSPACE = Path('/home/user/workspace')
NOTEBOOK = WORKSPACE / 'extract_features.ipynb'
INPUT_PDB = WORKSPACE / 'input.pdb'
FEATURES = WORKSPACE / 'features.csv'


def test_notebook_exists_and_valid():
    """Check if the Jupyter Notebook exists and is valid JSON."""
    notebook_path = '/home/user/workspace/extract_features.ipynb'
    assert os.path.isfile(notebook_path), f"Notebook missing: {notebook_path}"

    with open(notebook_path, 'r') as f:
        try:
            nb_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Notebook {notebook_path} is not a valid JSON file."

    assert "cells" in nb_data, "Notebook missing 'cells' key, might not be a valid Jupyter Notebook."


def test_features_csv_exists_and_correct():
    """Check if features.csv exists and contains the correct singular values."""
    csv_path = '/home/user/workspace/features.csv'
    assert os.path.isfile(csv_path), f"Features file missing: {csv_path}"

    with open(csv_path, 'r') as f:
        content = f.read().strip()

    expected_content = "3.0000,3.0000,1.0000,1.0000,1.0000"

    assert content == expected_content, f"Expected features.csv to contain '{expected_content}', but found '{content}'"


def _pdb_for_coordinates(coords):
    lines = []
    serial = 1
    for residue, (x, y, z) in enumerate(coords, start=1):
        # Distractor atoms ensure that only atoms whose atom-name field is CA are used.
        lines.append(
            f"ATOM  {serial:5d}  N   ALA A{residue:4d}    "
            f"{x + 0.321:8.3f}{y + 0.654:8.3f}{z + 0.987:8.3f}  1.00  0.00           N"
        )
        serial += 1
        lines.append(
            f"ATOM  {serial:5d}  CA  ALA A{residue:4d}    "
            f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C"
        )
        serial += 1
        lines.append(
            f"ATOM  {serial:5d}  CB  ALA A{residue:4d}    "
            f"{x - 0.432:8.3f}{y - 0.765:8.3f}{z - 0.246:8.3f}  1.00  0.00           C"
        )
        serial += 1
    return '\n'.join(lines) + '\n'


def _expected_features(coords):
    xyz = np.asarray(coords, dtype=float)
    distances = np.linalg.norm(xyz[:, None, :] - xyz[None, :, :], axis=2)
    adjacency = ((distances > 0.0) & (distances <= 8.0)).astype(float)
    singular_values = np.linalg.svd(adjacency, compute_uv=False)
    top_five = sorted(singular_values, reverse=True)[:5]
    return ','.join(f'{value:.4f}' for value in top_five)


def _execute_and_check(coords):
    INPUT_PDB.write_text(_pdb_for_coordinates(coords))
    if FEATURES.exists() or FEATURES.is_symlink():
        FEATURES.unlink()

    proc = subprocess.run(
        [
            'jupyter', 'nbconvert',
            '--to', 'notebook',
            '--execute',
            '--inplace',
            '--ExecutePreprocessor.timeout=120',
            '--ExecutePreprocessor.kernel_name=python3',
            str(NOTEBOOK),
        ],
        cwd=str(WORKSPACE),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert proc.returncode == 0, f'Notebook execution failed:\n{proc.stdout}'
    assert FEATURES.is_file(), 'Executing the notebook did not generate features.csv'

    expected = _expected_features(coords)
    raw = FEATURES.read_text()
    assert raw in (expected, expected + '\n', expected + '\r\n'), (
        f"Expected one CSV line '{expected}', but found {raw!r}"
    )


def test_z_notebook_executes_and_computes_fresh_inputs():
    """Execute the submitted notebook on unpredictable structures and verify its output."""
    original_input = INPUT_PDB.read_bytes()
    original_notebook = NOTEBOOK.read_bytes()
    original_features = FEATURES.read_bytes()

    rng = np.random.default_rng(int.from_bytes(os.urandom(16), 'big'))

    # Includes zero-distance, exactly-8.000, and 8.001-distance pairs.
    offset = np.round(rng.uniform(-20.0, 20.0, size=3), 3)
    boundary = np.asarray([
        [0.000, 0.000, 0.000],
        [8.000, 0.000, 0.000],
        [8.001, 0.000, 0.000],
        [0.000, 0.000, 0.000],
        [0.000, 6.000, 0.000],
        [0.000, 0.000, 6.000],
        [5.000, 5.000, 0.000],
        [5.000, 0.000, 5.000],
    ]) + offset
    boundary = np.round(boundary, 3)

    random_case_1 = np.round(rng.uniform(-5.0, 17.0, size=(10, 3)), 3)
    random_case_2 = np.round(rng.uniform(-12.0, 12.0, size=(12, 3)), 3)

    try:
        for coords in (boundary, random_case_1, random_case_2):
            _execute_and_check(coords)
    finally:
        INPUT_PDB.write_bytes(original_input)
        NOTEBOOK.write_bytes(original_notebook)
        FEATURES.write_bytes(original_features)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
