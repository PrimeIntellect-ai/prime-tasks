#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os

import numpy as np
from scipy import stats


def expected_pdb_bytes():
    # Recreate the immutable input produced by setup.sh so replacing the PDB
    # cannot simplify the analysis being verified.
    np.random.seed(123)
    n_residues = 200
    residues = ['ALA', 'GLY', 'VAL', 'LEU', 'ILE', 'PRO']
    pdb_lines = []
    for i in range(1, n_residues + 1):
        res_name = np.random.choice(
            residues, p=[0.3, 0.2, 0.15, 0.15, 0.1, 0.1]
        )
        if i == 1:
            coord = np.array([0.0, 0.0, 0.0])
        else:
            coord += np.random.randn(3) * 3.8
        line = (
            f"ATOM  {i:>5}  CA  {res_name:<3} A{i:>4}    "
            f"{coord[0]:8.3f}{coord[1]:8.3f}{coord[2]:8.3f}"
            "  1.00 20.00           C  "
        )
        pdb_lines.append(line)
    return ("\n".join(pdb_lines) + "\n").encode()


def test_results_json():
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), f"The file {results_path} does not exist."

    with open(results_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{results_path} is not a valid JSON file."

    expected_keys = {
        "com_x", "com_y", "com_z", "wasserstein_distance",
        "ks_statistic", "ks_pvalue"
    }
    actual_keys = set(results.keys())
    assert actual_keys == expected_keys, (
        f"results.json keys do not match the expected keys.\n"
        f"Missing: {expected_keys - actual_keys}\n"
        f"Unexpected: {actual_keys - expected_keys}"
    )

    for key in expected_keys:
        value = results[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), \
            f"{key} must be a JSON number."
        assert math.isfinite(value), f"{key} must be finite."

    coords = []
    ala_coords = []
    pdb_path = "/home/user/protein.pdb"
    assert os.path.exists(pdb_path), f"{pdb_path} is missing, cannot verify results."

    with open(pdb_path, "rb") as f:
        actual_pdb = f.read()
    assert actual_pdb == expected_pdb_bytes(), \
        "protein.pdb was modified from the input supplied by setup."

    with open(pdb_path, "r") as f:
        for line in f:
            if line.startswith("ATOM") and line[12:16].strip() == "CA":
                x = float(line[30:38])
                y = float(line[38:46])
                z = float(line[46:54])
                coords.append((x, y, z))
                if line[17:20].strip() == "ALA":
                    ala_coords.append((x, y, z))

    assert len(coords) > 0, "No CA atoms found in the PDB file."
    assert len(ala_coords) > 0, "No ALA CA atoms found in the PDB file."

    com_x = sum(c[0] for c in coords) / len(coords)
    com_y = sum(c[1] for c in coords) / len(coords)
    com_z = sum(c[2] for c in coords) / len(coords)

    distances = []
    for c in ala_coords:
        d = math.sqrt(
            (c[0] - com_x) ** 2
            + (c[1] - com_y) ** 2
            + (c[2] - com_z) ** 2
        )
        distances.append(d)

    distances.sort()
    n = len(distances)

    # Preserve the original independent KS-statistic computation.
    ks_stat = 0
    sigma = 15.0
    for i, d in enumerate(distances):
        cdf = 1.0 - math.exp(-(d ** 2) / (2.0 * sigma ** 2))
        d_plus = (i + 1) / n - cdf
        d_minus = cdf - i / n
        ks_stat = max(ks_stat, d_plus, d_minus)

    # Independently derive the SciPy p-value and seeded Wasserstein result.
    scipy_ks = stats.kstest(
        np.asarray(distances), "rayleigh", args=(0.0, 15.0)
    )
    theoretical = np.random.default_rng(42).rayleigh(scale=15.0, size=100000)
    computed_w_dist = stats.wasserstein_distance(distances, theoretical)

    tol = 0.0002

    assert abs(results["com_x"] - round(com_x, 4)) <= tol, \
        f"com_x is incorrect. Expected {round(com_x, 4)}, got {results['com_x']}"
    assert abs(results["com_y"] - round(com_y, 4)) <= tol, \
        f"com_y is incorrect. Expected {round(com_y, 4)}, got {results['com_y']}"
    assert abs(results["com_z"] - round(com_z, 4)) <= tol, \
        f"com_z is incorrect. Expected {round(com_z, 4)}, got {results['com_z']}"
    assert abs(results["ks_statistic"] - round(ks_stat, 4)) <= tol, \
        f"ks_statistic is incorrect. Expected {round(ks_stat, 4)}, got {results['ks_statistic']}"

    # Preserve the original known-value Wasserstein assertion.
    expected_w_dist = 8.9221
    assert abs(results["wasserstein_distance"] - expected_w_dist) <= 0.005, \
        f"wasserstein_distance is incorrect. Expected ~{expected_w_dist}, got {results['wasserstein_distance']}"

    expected_pvalue = 0.0
    assert abs(results["ks_pvalue"] - expected_pvalue) <= tol, \
        f"ks_pvalue is incorrect. Expected ~{expected_pvalue}, got {results['ks_pvalue']}"

    assert abs(results["wasserstein_distance"] - round(computed_w_dist, 4)) <= tol, \
        f"wasserstein_distance is incorrect. Expected {round(computed_w_dist, 4)}, got {results['wasserstein_distance']}"
    assert abs(results["ks_statistic"] - round(float(scipy_ks.statistic), 4)) <= tol, \
        f"ks_statistic disagrees with SciPy. Expected {round(float(scipy_ks.statistic), 4)}, got {results['ks_statistic']}"
    assert abs(results["ks_pvalue"] - round(float(scipy_ks.pvalue), 4)) <= tol, \
        f"ks_pvalue is incorrect. Expected {round(float(scipy_ks.pvalue), 4)}, got {results['ks_pvalue']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
