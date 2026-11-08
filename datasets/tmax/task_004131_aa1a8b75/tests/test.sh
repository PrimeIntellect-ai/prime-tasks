#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import sys

import numpy as np
import pytest
from scipy.optimize import nnls

RESULTS_PATH = "/home/user/results.json"
FASTA_PATH = "/home/user/proteins.fasta"
SPECTRUM_PATH = "/home/user/exp_spectrum.npy"


def parse_fasta(path):
    sequences = []
    current = []
    with open(path, "r") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if current:
                    sequences.append("".join(current))
                    current = []
            else:
                current.append(line)
    if current:
        sequences.append("".join(current))
    return sequences


def protein_spectrum(sequence):
    x = np.linspace(0, 100, 1000)
    spectrum = np.zeros_like(x)
    for amino_acid in sequence:
        mu = ord(amino_acid)
        spectrum += np.exp(-((x - mu) ** 2) / (2 * (2.0 ** 2)))
    return spectrum


def recompute_expected(fasta_path=FASTA_PATH, spectrum_path=SPECTRUM_PATH):
    sequences = parse_fasta(fasta_path)
    assert len(sequences) == 5, f"Expected 5 FASTA sequences, got {len(sequences)}"
    experimental = np.load(spectrum_path, allow_pickle=False)
    assert experimental.shape == (1000,), f"Unexpected spectrum shape: {experimental.shape}"
    design = np.column_stack([protein_spectrum(seq) for seq in sequences])
    weights, _ = nnls(design, experimental)
    residuals = experimental - design @ weights
    return weights, float(np.mean(residuals)), float(np.std(residuals, ddof=0))


def load_results(path=RESULTS_PATH):
    with open(path, "r") as f:
        return json.load(f)


def assert_matches_recomputed(data, expected):
    assert set(data.keys()) == {"weights", "residual_mean", "residual_std"}, \
        "results.json must contain exactly the required keys"
    assert isinstance(data["weights"], list) and len(data["weights"]) == 5
    assert all(isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)
               for v in data["weights"])
    assert isinstance(data["residual_mean"], (int, float)) and not isinstance(data["residual_mean"], bool)
    assert isinstance(data["residual_std"], (int, float)) and not isinstance(data["residual_std"], bool)
    assert math.isfinite(data["residual_mean"])
    assert math.isfinite(data["residual_std"])
    weights, mean, std = expected
    np.testing.assert_allclose(np.asarray(data["weights"], dtype=float), weights,
                               rtol=1e-6, atol=1e-8)
    np.testing.assert_allclose(float(data["residual_mean"]), mean,
                               rtol=1e-6, atol=1e-8)
    np.testing.assert_allclose(float(data["residual_std"]), std,
                               rtol=1e-6, atol=1e-8)


def find_python_scripts():
    scripts = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d != "__pycache__" and not d.startswith(".")]
        for name in files:
            path = os.path.join(root, name)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            is_python = name.endswith(".py")
            if not is_python:
                try:
                    with open(path, "rb") as f:
                        first_line = f.readline(256).lower()
                    is_python = first_line.startswith(b"#!") and b"python" in first_line
                except OSError:
                    pass
            if is_python:
                scripts.append(path)
    return sorted(scripts)


def test_results_json_exists():
    """Check if the results.json file exists."""
    assert os.path.isfile(RESULTS_PATH), f"Missing results file: {RESULTS_PATH}"


def test_results_json_content():
    """Keep the original checks and compare against the actual input-derived solution."""
    assert os.path.isfile(RESULTS_PATH), "results.json does not exist."

    with open(RESULTS_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("results.json is not a valid JSON file.")

    assert "weights" in data, "Missing 'weights' key in results.json"
    assert "residual_mean" in data, "Missing 'residual_mean' key in results.json"
    assert "residual_std" in data, "Missing 'residual_std' key in results.json"

    weights = data["weights"]
    mean = data["residual_mean"]
    std = data["residual_std"]

    assert isinstance(weights, list), "'weights' must be a list"
    assert len(weights) == 5, f"Expected 5 weights, got {len(weights)}"

    expected_weights = [1.5, 0.0, 0.8, 2.2, 0.0]
    for i, (w, ew) in enumerate(zip(weights, expected_weights)):
        assert isinstance(w, (int, float)), f"Weight at index {i} must be a float"
        assert abs(w - ew) < 0.1, f"Weight at index {i} ({w}) does not match expected {ew} within 0.1 tolerance"

    assert isinstance(mean, (int, float)), "'residual_mean' must be a float"
    assert abs(mean - 0.0) < 0.05, f"Mean {mean} is too far from expected 0.0 (tolerance 0.05)"

    assert isinstance(std, (int, float)), "'residual_std' must be a float"
    assert abs(std - 0.05) < 0.02, f"Std {std} is too far from expected 0.05 (tolerance 0.02)"

    assert_matches_recomputed(data, recompute_expected())


def test_submitted_script_executes_on_fresh_inputs():
    scripts = find_python_scripts()
    assert scripts, "No submitted Python analysis script found under /home/user"

    original_fasta = open(FASTA_PATH, "rb").read()
    original_spectrum = open(SPECTRUM_PATH, "rb").read()
    original_results = open(RESULTS_PATH, "rb").read() if os.path.isfile(RESULTS_PATH) else None

    challenge_fasta = (
        ">Challenge_1\nAAAAF\n"
        ">Challenge_2\nFFFFL\n"
        ">Challenge_3\nLLLLR\n"
        ">Challenge_4\nRRRRX\n"
        ">Challenge_5\nXXXXA\n"
    )
    challenge_sequences = ["AAAAF", "FFFFL", "LLLLR", "RRRRX", "XXXXA"]
    rng = np.random.default_rng()
    challenge_weights = rng.uniform(0.2, 2.8, size=5)
    challenge_design = np.column_stack([protein_spectrum(seq) for seq in challenge_sequences])
    challenge_spectrum = challenge_design @ challenge_weights + rng.normal(0.0, 0.031, 1000)

    passed_script = None
    errors = []
    try:
        for script in scripts:
            with open(FASTA_PATH, "w") as f:
                f.write(challenge_fasta)
            np.save(SPECTRUM_PATH, challenge_spectrum)
            if os.path.exists(RESULTS_PATH):
                os.remove(RESULTS_PATH)

            try:
                completed = subprocess.run(
                    [sys.executable, script], cwd="/home/user",
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=30
                )
                if completed.returncode != 0:
                    errors.append(f"{script}: exited {completed.returncode}")
                    continue
                if not os.path.isfile(RESULTS_PATH):
                    errors.append(f"{script}: did not create results.json")
                    continue
                data = load_results()
                assert_matches_recomputed(data, recompute_expected())
                passed_script = script
                break
            except Exception as exc:
                errors.append(f"{script}: {exc}")
    finally:
        with open(FASTA_PATH, "wb") as f:
            f.write(original_fasta)
        with open(SPECTRUM_PATH, "wb") as f:
            f.write(original_spectrum)
        if original_results is None:
            if os.path.exists(RESULTS_PATH):
                os.remove(RESULTS_PATH)
        else:
            with open(RESULTS_PATH, "wb") as f:
                f.write(original_results)

    assert passed_script is not None, "No submitted Python script produced correct recomputed results on fresh inputs: " + "; ".join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
