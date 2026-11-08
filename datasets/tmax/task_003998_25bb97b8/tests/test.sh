#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import tempfile

import numpy as np
from scipy import stats


def test_compiled_executable_exists():
    path = "/home/user/generate_pdb"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "generate_pdb is not a compiled ELF executable."


def test_generated_pdb_matches_compiled_generator():
    source = "/home/user/generate_pdb.c"
    executable = "/home/user/generate_pdb"
    pdb_path = "/home/user/simulated.pdb"

    with tempfile.TemporaryDirectory() as tmpdir:
        reference_executable = os.path.join(tmpdir, "generate_pdb_reference")
        subprocess.run(
            ["gcc", source, "-o", reference_executable, "-lm"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        expected = subprocess.run(
            [reference_executable],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        ).stdout
        actual_generator_output = subprocess.run(
            [executable],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        ).stdout

    with open(pdb_path, "rb") as f:
        submitted_pdb = f.read()

    assert actual_generator_output == expected, "generate_pdb does not produce the output of the supplied C source."
    assert submitted_pdb == actual_generator_output, "simulated.pdb was not generated from /home/user/generate_pdb."


def test_simulated_pdb_exists():
    path = "/home/user/simulated.pdb"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."

    with open(path, "r") as f:
        content = f.read()
    assert "ATOM" in content, "simulated.pdb does not seem to contain ATOM records."

    lines = content.splitlines()
    assert len(lines) == 1000, f"Expected 1000 PDB records, found {len(lines)}."
    assert all(line.startswith("ATOM  ") for line in lines), "Every generated record must be an ATOM record."
    assert all(len(line) >= 66 for line in lines), "ATOM records are too short to contain a standard B-factor field."
    for line in lines:
        float(line[60:66])


def test_analysis_results_json():
    path = "/home/user/analysis_results.json"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."

    try:
        with open(path, "r") as f:
            results = json.load(f)
    except json.JSONDecodeError:
        assert False, f"File {path} is not valid JSON."

    assert "best_fit" in results, "Key 'best_fit' missing in analysis_results.json"
    assert "aic_normal" in results, "Key 'aic_normal' missing in analysis_results.json"
    assert "aic_gamma" in results, "Key 'aic_gamma' missing in analysis_results.json"
    assert set(results) == {"best_fit", "aic_normal", "aic_gamma"}, "analysis_results.json must contain exactly the requested keys."

    assert results["best_fit"] == "Gamma", f"Expected 'best_fit' to be 'Gamma', got {results['best_fit']}"

    assert isinstance(results["aic_normal"], (int, float)), "aic_normal must be a number"
    assert isinstance(results["aic_gamma"], (int, float)), "aic_gamma must be a number"
    assert not isinstance(results["aic_normal"], bool), "aic_normal must be a number"
    assert not isinstance(results["aic_gamma"], bool), "aic_gamma must be a number"
    assert math.isfinite(results["aic_normal"]), "aic_normal must be finite"
    assert math.isfinite(results["aic_gamma"]), "aic_gamma must be finite"

    assert results["aic_gamma"] < results["aic_normal"], "Expected aic_gamma to be less than aic_normal"

    with open("/home/user/simulated.pdb", "r") as f:
        b_factors = np.asarray(
            [float(line[60:66]) for line in f if line.startswith("ATOM")],
            dtype=float,
        )

    assert b_factors.size > 0, "No ATOM B-factors were parsed from simulated.pdb."

    normal_params = stats.norm.fit(b_factors)
    gamma_params = stats.gamma.fit(b_factors)
    normal_log_likelihood = float(np.sum(stats.norm.logpdf(b_factors, *normal_params)))
    gamma_log_likelihood = float(np.sum(stats.gamma.logpdf(b_factors, *gamma_params)))
    expected_normal = round(2 * 2 - 2 * normal_log_likelihood, 2)
    expected_gamma = round(2 * 3 - 2 * gamma_log_likelihood, 2)
    expected_best = "Normal" if expected_normal < expected_gamma else "Gamma"

    assert results["aic_normal"] == expected_normal, (
        f"aic_normal must be {expected_normal}, computed from simulated.pdb; got {results['aic_normal']}"
    )
    assert results["aic_gamma"] == expected_gamma, (
        f"aic_gamma must be {expected_gamma}, computed from simulated.pdb; got {results['aic_gamma']}"
    )
    assert results["best_fit"] == expected_best, (
        f"best_fit must be {expected_best} based on the recomputed AIC values."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
