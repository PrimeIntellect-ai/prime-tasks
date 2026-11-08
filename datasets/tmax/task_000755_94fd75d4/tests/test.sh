#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os

import numpy as np
import pytest

OUTPUT_PATH = "/home/user/posterior_stats.json"
FASTA_PATH = "/home/user/sequences.fasta"
OBSERVATIONS_PATH = "/home/user/observations.csv"


def calculate_expected_stats():
    alanine_counts = {}
    current_id = None
    sequence_parts = []

    with open(FASTA_PATH, "r") as fasta:
        for raw_line in fasta:
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if current_id is not None:
                    alanine_counts[current_id] = "".join(sequence_parts).count("A")
                current_id = line[1:].split()[0]
                sequence_parts = []
            else:
                sequence_parts.append(line)

    if current_id is not None:
        alanine_counts[current_id] = "".join(sequence_parts).count("A")

    mutation_totals = {}
    with open(OBSERVATIONS_PATH, "r", newline="") as observations:
        for row in csv.DictReader(observations):
            seq_id = row["seq_id"]
            mutation_totals[seq_id] = mutation_totals.get(seq_id, 0) + int(row["mutations"])

    assert mutation_totals, "No observations were found."
    assert set(mutation_totals).issubset(alanine_counts), "An observation references an unknown sequence."

    total_mutations = sum(mutation_totals.values())
    total_alanines = sum(alanine_counts[seq_id] for seq_id in mutation_totals)

    np.random.seed(42)
    current_lambda = 1.0
    samples = np.empty(50000, dtype=float)

    for iteration in range(50000):
        proposed_lambda = np.random.normal(current_lambda, 0.5)
        if 0.0 < proposed_lambda <= 10.0:
            log_acceptance_ratio = (
                total_mutations * (np.log(proposed_lambda) - np.log(current_lambda))
                - total_alanines * (proposed_lambda - current_lambda)
            )
            if np.log(np.random.rand()) < log_acceptance_ratio:
                current_lambda = proposed_lambda
        samples[iteration] = current_lambda

    retained = samples[10000:]
    return round(float(np.mean(retained)), 3), round(float(np.std(retained)), 3)


EXPECTED_MEAN, EXPECTED_STD = calculate_expected_stats()


def test_posterior_stats_file_exists():
    assert os.path.exists(OUTPUT_PATH), f"The file {OUTPUT_PATH} does not exist."


def test_posterior_stats_content():
    assert os.path.exists(OUTPUT_PATH), f"The file {OUTPUT_PATH} does not exist."

    with open(OUTPUT_PATH, "r") as output:
        try:
            data = json.load(output)
        except json.JSONDecodeError:
            pytest.fail(f"The file {OUTPUT_PATH} is not a valid JSON file.")

    assert "mean" in data, "The key 'mean' is missing from the JSON file."
    assert "std" in data, "The key 'std' is missing from the JSON file."

    mean = data["mean"]
    std = data["std"]

    assert isinstance(mean, (int, float)) and not isinstance(mean, bool), \
        f"Expected 'mean' to be a number, got {type(mean)}."
    assert isinstance(std, (int, float)) and not isinstance(std, bool), \
        f"Expected 'std' to be a number, got {type(std)}."
    assert math.isfinite(mean), "The mean must be finite."
    assert math.isfinite(std), "The standard deviation must be finite."

    assert 2.70 <= mean <= 2.82, \
        f"The calculated mean ({mean}) is not within the expected range [2.70, 2.82]."
    assert 0.20 <= std <= 0.25, \
        f"The calculated std ({std}) is not within the expected range [0.20, 0.25]."

    assert mean == EXPECTED_MEAN, \
        f"Expected the reproducible rounded mean {EXPECTED_MEAN}, got {mean}."
    assert std == EXPECTED_STD, \
        f"Expected the reproducible rounded std {EXPECTED_STD}, got {std}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
