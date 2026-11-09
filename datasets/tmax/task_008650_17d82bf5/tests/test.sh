#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import math
import os
import subprocess
import sys

import numpy as np
import pytest
from scipy.stats import linregress, wasserstein_distance
from sklearn.mixture import GaussianMixture

RESULTS_PATH = "/home/user/results.json"
SCRIPT_PATH = "/home/user/analyze_protein.py"
PDB_PATH = "/home/user/protein.pdb"


def original_pdb_contents():
    """Reproduce the deterministic input created by setup.sh."""
    np.random.seed(123)
    output = io.StringIO()
    atom_id = 1
    residues = ["VAL", "ALA", "VAL", "GLY", "VAL", "ALA", "VAL", "ALA", "VAL", "VAL", "ALA", "ALA"] * 10
    for res_id, res_name in enumerate(residues):
        x, y, z = np.random.rand(3) * 50
        bfactor = np.random.rand() * 100
        output.write(
            f"ATOM  {atom_id:5d}  CA  {res_name} A{res_id:4d}    "
            f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00{bfactor:6.2f}           C\n"
        )
        atom_id += 1
    return output.getvalue()


def assert_original_pdb():
    assert os.path.isfile(PDB_PATH), f"The input file {PDB_PATH} does not exist."
    with open(PDB_PATH, "r") as f:
        actual = f.read()
    assert actual == original_pdb_contents(), "protein.pdb was modified from the supplied input."


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert_original_pdb()
    assert os.path.isfile(SCRIPT_PATH), f"The required script {SCRIPT_PATH} does not exist."
    assert not os.path.islink(SCRIPT_PATH), f"{SCRIPT_PATH} must be a regular submitted file."

    if os.path.lexists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    try:
        completed = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("analyze_protein.py did not finish within 120 seconds.")

    assert completed.returncode == 0, (
        "analyze_protein.py failed.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    assert_original_pdb()


def load_results():
    assert os.path.isfile(RESULTS_PATH), f"The expected output file {RESULTS_PATH} does not exist."
    with open(RESULTS_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {RESULTS_PATH} does not contain valid JSON.")


def independently_compute_results():
    all_coords = []
    val_coords = []
    val_bfactors = []
    ala_bfactors = []

    with open(PDB_PATH, "r") as f:
        for line in f:
            if line[0:6].strip() not in {"ATOM", "HETATM"}:
                continue
            if line[12:16].strip() != "CA":
                continue

            residue = line[17:20].strip()
            coord = [float(line[30:38]), float(line[38:46]), float(line[46:54])]
            bfactor = float(line[60:66])
            all_coords.append(coord)

            if residue == "VAL":
                val_coords.append(coord)
                val_bfactors.append(bfactor)
            elif residue == "ALA":
                ala_bfactors.append(bfactor)

    all_coords = np.asarray(all_coords, dtype=float)
    val_coords = np.asarray(val_coords, dtype=float)
    val_bfactors = np.asarray(val_bfactors, dtype=float)
    ala_bfactors = np.asarray(ala_bfactors, dtype=float)

    assert all_coords.shape == (120, 3)
    assert val_coords.shape == (50, 3)
    assert len(ala_bfactors) == 50

    center_of_mass = np.mean(all_coords, axis=0)
    model = GaussianMixture(n_components=3, random_state=42)
    model.fit(val_coords)
    weights = sorted((float(v) for v in model.weights_), reverse=True)

    distances = np.linalg.norm(val_coords - center_of_mass, axis=1)
    slope = float(linregress(distances, val_bfactors).slope)
    wd = float(wasserstein_distance(val_bfactors, ala_bfactors))

    return {
        "gmm_weights": [round(v, 4) for v in weights],
        "regression_slope": round(slope, 4),
        "wasserstein_distance": round(wd, 4),
    }


def test_results_json_exists_and_valid():
    """Check that results.json exists and contains the correct schema and valid data types."""
    data = load_results()

    expected_keys = {"gmm_weights", "regression_slope", "wasserstein_distance"}
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"The JSON file is missing the following keys: {missing_keys}"

    gmm_weights = data["gmm_weights"]
    assert isinstance(gmm_weights, list), "'gmm_weights' must be a list."
    assert len(gmm_weights) == 3, "'gmm_weights' must contain exactly 3 elements."
    assert all(isinstance(w, (int, float)) for w in gmm_weights), "All elements in 'gmm_weights' must be numbers."
    assert all(math.isfinite(w) for w in gmm_weights), "All GMM weights must be finite."
    assert gmm_weights == sorted(gmm_weights, reverse=True), "'gmm_weights' must be sorted in descending order."

    assert isinstance(data["regression_slope"], (int, float)), "'regression_slope' must be a number."
    assert math.isfinite(data["regression_slope"]), "'regression_slope' must be finite."

    assert isinstance(data["wasserstein_distance"], (int, float)), "'wasserstein_distance' must be a number."
    assert math.isfinite(data["wasserstein_distance"]), "'wasserstein_distance' must be finite."
    assert data["wasserstein_distance"] >= 0, "'wasserstein_distance' cannot be negative."


def test_results_json_precision():
    """Check that the results are rounded to 4 decimal places where possible."""
    if not os.path.isfile(RESULTS_PATH):
        pytest.skip("results.json not found")

    data = load_results()
    for weight in data["gmm_weights"]:
        assert round(weight, 4) == weight, f"GMM weight {weight} is not rounded to 4 decimal places."

    assert round(data["regression_slope"], 4) == data["regression_slope"], "regression_slope is not rounded to 4 decimal places."
    assert round(data["wasserstein_distance"], 4) == data["wasserstein_distance"], "wasserstein_distance is not rounded to 4 decimal places."


def test_results_match_independent_analysis():
    data = load_results()
    expected = independently_compute_results()
    assert data["gmm_weights"] == expected["gmm_weights"], "GMM weights do not match the supplied PDB analysis."
    assert data["regression_slope"] == expected["regression_slope"], "Regression slope does not match the supplied PDB analysis."
    assert data["wasserstein_distance"] == expected["wasserstein_distance"], "Wasserstein distance does not match the supplied PDB analysis."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
