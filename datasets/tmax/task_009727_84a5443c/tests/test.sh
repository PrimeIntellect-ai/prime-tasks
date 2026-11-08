#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import stat
import subprocess
import sys
from pathlib import Path

import numpy as np
from scipy.stats import ks_2samp

SCRIPT_PATH = Path("/home/user/profile_matrix.py")
PDB_PATH = Path("/home/user/data/protein.pdb")
REPORT_PATH = Path("/home/user/profiling_report.json")
EXPECTED_KEYS = {
    "num_ca_atoms",
    "min_eigenvalue_unreg",
    "condition_number_unreg",
    "trace_reg",
    "top_3_eigenvalues_reg",
    "ks_statistic",
}


def parse_ca_coordinates(pdb_bytes):
    coords = []
    for line in pdb_bytes.decode("utf-8").splitlines():
        if line.startswith("ATOM") and len(line) >= 54 and line[12:16] == " CA ":
            coords.append([
                float(line[30:38]),
                float(line[38:46]),
                float(line[46:54]),
            ])
    return np.asarray(coords, dtype=float)


def expected_metrics(pdb_bytes):
    coords = parse_ca_coordinates(pdb_bytes)
    assert len(coords) >= 3, "Verifier test input must contain at least three CA atoms"
    delta = coords[:, None, :] - coords[None, :, :]
    distances = np.linalg.norm(delta, axis=2)
    matrix = np.exp(-(distances ** 2) / 2.0)
    eigenvalues = np.linalg.eigvalsh(matrix)
    matrix_reg = matrix + 1e-5 * np.eye(len(coords))
    eigenvalues_reg = np.linalg.eigvalsh(matrix_reg)
    return {
        "num_ca_atoms": len(coords),
        "min_eigenvalue_unreg": float(np.min(eigenvalues)),
        "condition_number_unreg": float(np.linalg.cond(matrix, 2)),
        "trace_reg": float(np.trace(matrix_reg)),
        "top_3_eigenvalues_reg": [float(x) for x in eigenvalues_reg[-3:][::-1]],
        "ks_statistic": float(ks_2samp(eigenvalues, eigenvalues_reg).statistic),
    }


def run_submission():
    if REPORT_PATH.exists():
        REPORT_PATH.unlink()
    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"profile_matrix.py failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert REPORT_PATH.exists(), f"Report file {REPORT_PATH} was not created."
    assert REPORT_PATH.is_file(), f"Report path {REPORT_PATH} is not a regular file."
    try:
        with REPORT_PATH.open("r") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"File {REPORT_PATH} does not contain valid JSON: {exc}")


def assert_close(actual, expected, name):
    assert type(actual) in (int, float), f"{name} must be a number"
    assert math.isfinite(float(actual)), f"{name} must be finite"
    assert math.isclose(float(actual), float(expected), rel_tol=1e-6, abs_tol=1e-9), (
        f"Expected {name} approximately {expected}, got {actual}"
    )


def validate_computed_report(ans, expected):
    assert isinstance(ans, dict), "The report must be a JSON object"
    missing_keys = EXPECTED_KEYS - set(ans.keys())
    assert not missing_keys, f"Missing keys in JSON report: {missing_keys}"
    assert set(ans.keys()) == EXPECTED_KEYS, (
        f"JSON report must contain exactly the required keys; got {set(ans.keys())}"
    )

    assert type(ans["num_ca_atoms"]) is int, "num_ca_atoms must be an integer"
    assert ans["num_ca_atoms"] == expected["num_ca_atoms"], (
        f"Expected {expected['num_ca_atoms']} CA atoms, got {ans['num_ca_atoms']}"
    )
    assert_close(ans["min_eigenvalue_unreg"], expected["min_eigenvalue_unreg"], "min_eigenvalue_unreg")
    assert_close(ans["condition_number_unreg"], expected["condition_number_unreg"], "condition_number_unreg")
    assert_close(ans["trace_reg"], expected["trace_reg"], "trace_reg")
    assert_close(ans["ks_statistic"], expected["ks_statistic"], "ks_statistic")

    top_3 = ans["top_3_eigenvalues_reg"]
    assert isinstance(top_3, list) and len(top_3) == 3, "top_3_eigenvalues_reg must be a list of 3 floats"
    assert all(type(x) in (int, float) for x in top_3), "top_3_eigenvalues_reg elements must be numbers"
    for index, (actual, wanted) in enumerate(zip(top_3, expected["top_3_eigenvalues_reg"])):
        assert_close(actual, wanted, f"top_3_eigenvalues_reg[{index}]")


def test_profile_script_and_report():
    assert SCRIPT_PATH.exists(), f"Required script {SCRIPT_PATH} does not exist"
    assert stat.S_ISREG(os.lstat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} must be a regular file"

    original_pdb = PDB_PATH.read_bytes()
    original_expected = expected_metrics(original_pdb)

    alternate_pdb = b"""ATOM      1  CA  ALA A   1       0.000   0.000   0.000  1.00  0.00           C  
ATOM      2  CB  ALA A   1       9.000   9.000   9.000  1.00  0.00           C  
ATOM      3  CA  ALA A   2       0.700   1.100   0.200  1.00  0.00           C  
ATOM      4  CA  ALA A   3       1.800  -0.400   0.900  1.00  0.00           C  
ATOM      5  CA  ALA A   4      -1.200   0.300   2.000  1.00  0.00           C  
ATOM      6  CA  ALA A   5       2.500   1.700  -0.800  1.00  0.00           C  
ATOM      7  CA  ALA A   6      -0.600  -1.500   0.400  1.00  0.00           C  
"""

    try:
        ans = run_submission()
        validate_computed_report(ans, original_expected)

        # Preserve the original verifier's assertions for the supplied PDB.
        assert ans["num_ca_atoms"] == 7, f"Expected 7 CA atoms, got {ans['num_ca_atoms']}"
        expected_trace = 7.00007
        assert math.isclose(ans["trace_reg"], expected_trace, rel_tol=1e-4), \
            f"Expected trace_reg ~ {expected_trace}, got {ans['trace_reg']}"
        min_eval = ans["min_eigenvalue_unreg"]
        assert isinstance(min_eval, (int, float)), "min_eigenvalue_unreg must be a number"
        assert min_eval < 1e-5, f"Expected min_eigenvalue_unreg to be near 0, got {min_eval}"
        cond_unreg = ans["condition_number_unreg"]
        assert isinstance(cond_unreg, (int, float)), "condition_number_unreg must be a number"
        assert cond_unreg > 1e14, f"Expected condition_number_unreg to be very large (>1e14), got {cond_unreg}"
        top_3 = ans["top_3_eigenvalues_reg"]
        assert isinstance(top_3, list) and len(top_3) == 3, "top_3_eigenvalues_reg must be a list of 3 floats"
        assert all(isinstance(x, (int, float)) for x in top_3), "top_3_eigenvalues_reg elements must be numbers"
        assert top_3[0] >= top_3[1] >= top_3[2], "top_3_eigenvalues_reg must be sorted in descending order"
        assert top_3[2] > 0, "Top eigenvalues should be positive"
        ks_stat = ans["ks_statistic"]
        assert isinstance(ks_stat, (int, float)), "ks_statistic must be a number"
        assert 0.0 <= ks_stat <= 1.0, f"KS statistic must be between 0 and 1, got {ks_stat}"

        PDB_PATH.write_bytes(alternate_pdb)
        alternate_ans = run_submission()
        validate_computed_report(alternate_ans, expected_metrics(alternate_pdb))
    finally:
        PDB_PATH.write_bytes(original_pdb)

    # Leave and verify the requested report for the original supplied input.
    final_ans = run_submission()
    validate_computed_report(final_ans, original_expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
