#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import numpy as np
import pytest

SCRIPT = "/home/user/mcmc_regression.py"
FASTA = "/home/user/sequences.fasta"
REFERENCE = "/home/user/reference_weights.csv"
RESULTS = "/home/user/results.log"


def run_submission():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"{SCRIPT} failed when executed.\nstdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULTS), (
        f"Executing {SCRIPT} did not create the required {RESULTS}."
    )


def parse_results():
    with open(RESULTS, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 5, (
        f"Expected exactly 5 lines (1 header, 4 features) in {RESULTS}, "
        f"found {len(lines)}."
    )
    assert lines[0] == "Feature,AbsDiff", (
        f"Header in {RESULTS} is incorrect. Expected 'Feature,AbsDiff', "
        f"got '{lines[0]}'."
    )

    parsed_diffs = {}
    for line in lines[1:]:
        parts = line.split(",")
        assert len(parts) == 2, f"Line '{line}' is not in 'Feature,AbsDiff' format."
        feature, diff_str = parts
        try:
            diff = float(diff_str)
        except ValueError:
            pytest.fail(f"Value '{diff_str}' for feature '{feature}' is not a valid float.")
        assert np.isfinite(diff), f"AbsDiff for '{feature}' must be finite."
        parsed_diffs[feature] = diff

    for feature in ["A", "C", "G", "T"]:
        assert feature in parsed_diffs, f"Feature '{feature}' is missing from {RESULTS}."
    return parsed_diffs


def reference_mcmc(sequences, references):
    np.random.seed(42)
    y = np.array([2.5, 1.2, 2.0, 1.8])
    X = np.array([
        [s.count("A"), s.count("C"), s.count("G"), s.count("T")]
        for s in sequences
    ])
    beta = np.linalg.inv(X.T @ X) @ X.T @ y
    samples = np.zeros((10000, 4))
    for i in range(10000):
        proposal = beta + np.random.normal(0, 0.1, size=beta.shape)
        ll_current = -0.5 * np.sum((y - X @ beta) ** 2)
        ll_proposal = -0.5 * np.sum((y - X @ proposal) ** 2)
        if np.log(np.random.uniform()) < (ll_proposal - ll_current):
            beta = proposal
        samples[i, :] = beta
    means = np.mean(samples[2000:, :], axis=0)
    return {
        feature: round(abs(means[i] - references[feature]), 2)
        for i, feature in enumerate(["A", "C", "G", "T"])
    }


def test_script_and_results():
    assert os.path.exists(SCRIPT), f"Required script {SCRIPT} does not exist."
    mode = os.lstat(SCRIPT).st_mode
    assert stat.S_ISREG(mode) and not os.path.islink(SCRIPT), (
        f"{SCRIPT} must be a regular Python source file."
    )
    with open(SCRIPT, "rb") as f:
        source = f.read()
    compile(source, SCRIPT, "exec")

    original_fasta = open(FASTA, "rb").read()
    original_reference = open(REFERENCE, "rb").read()
    try:
        # Execute the repaired artifact on the original task data.
        run_submission()
        parsed_diffs = parse_results()

        # Preserve the original verifier's expected-value assertions.
        expected_diffs = {
            "A": 0.10,
            "C": 0.00,
            "G": 0.00,
            "T": 0.00,
        }
        tolerance = 0.05
        for feature, expected_val in expected_diffs.items():
            actual_val = parsed_diffs[feature]
            assert abs(actual_val - expected_val) <= tolerance, (
                f"AbsDiff for '{feature}' is {actual_val}, expected "
                f"~{expected_val} (within {tolerance})."
            )

        # Exercise the script on alternate full-rank observations and references.
        # The expected answers are independently derived rather than hardcoded.
        challenge_sequences = ["AAAA", "CCCC", "GGGG", "TTTT"]
        challenge_references = {"A": 1.30, "C": -0.40, "G": 1.10, "T": -0.20}
        with open(FASTA, "w") as f:
            for i, sequence in enumerate(challenge_sequences, 1):
                f.write(f">challenge{i}\n{sequence}\n")
        with open(REFERENCE, "w") as f:
            f.write("Feature,ReferenceWeight\n")
            for feature in ["A", "C", "G", "T"]:
                f.write(f"{feature},{challenge_references[feature]:.2f}\n")

        expected_challenge = reference_mcmc(challenge_sequences, challenge_references)
        run_submission()
        actual_challenge = parse_results()
        for feature in ["A", "C", "G", "T"]:
            assert abs(actual_challenge[feature] - expected_challenge[feature]) <= 0.05, (
                f"On alternate input, AbsDiff for '{feature}' is "
                f"{actual_challenge[feature]}, expected approximately "
                f"{expected_challenge[feature]}."
            )
    finally:
        with open(FASTA, "wb") as f:
            f.write(original_fasta)
        with open(REFERENCE, "wb") as f:
            f.write(original_reference)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
