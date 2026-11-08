#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import stat
import string
import subprocess
import pytest

SCRIPT_PATH = "/home/user/run_model_test.py"
FASTA_PATH = "/home/user/genes.fasta"
REPORT_PATH = "/home/user/regression_report.json"


def expected_records(seqs):
    expected = []
    for sid, seq in seqs:
        L = len(seq)
        gc_count = seq.count("G") + seq.count("C")
        gc_frac = gc_count / L
        alpha = 1000.0 / L
        gamma = 0.05 + 2.0 * abs(gc_frac - 0.5)
        ana_M50 = (alpha / gamma) * (1 - math.exp(-gamma * 50))

        dt = 0.1
        M = 0.0
        for _ in range(500):
            M += (alpha - gamma * M) * dt
        num_M50 = M

        M_prev = 0.0
        for _ in range(499):
            M_prev += (alpha - gamma * M_prev) * dt
        num_deriv = (num_M50 - M_prev) / dt

        expected.append({
            "seq_id": sid,
            "analytical_M50": ana_M50,
            "numerical_M50": num_M50,
            "numerical_derivative_M50": num_deriv,
            "passed_regression": abs(ana_M50 - num_M50) < 1.0,
        })
    return expected


def write_fasta(seqs):
    with open(FASTA_PATH, "w") as f:
        for sid, seq in seqs:
            f.write(f">{sid}\n")
            # Use ordinary wrapped FASTA sequence lines.
            for start in range(0, len(seq), 13):
                f.write(seq[start:start + 13] + "\n")


def run_submission():
    if os.path.lexists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"run_model_test.py exited with {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert os.path.exists(REPORT_PATH), f"File {REPORT_PATH} does not exist after running the script."


def check_report(seqs):
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON.")

    assert isinstance(data, list), "JSON root must be an array."
    assert len(data) == len(seqs), f"Expected {len(seqs)} records in the JSON array, found {len(data)}."

    expected = expected_records(seqs)
    expected_keys = {
        "seq_id",
        "analytical_M50",
        "numerical_M50",
        "numerical_derivative_M50",
        "passed_regression",
    }

    for i, ((sid, _seq), wanted) in enumerate(zip(seqs, expected)):
        record = data[i]
        assert isinstance(record, dict), f"Record {i} must be a JSON object."
        assert set(record.keys()) == expected_keys, f"Record {i} keys {set(record.keys())} do not match expected {expected_keys}."
        assert record["seq_id"] == sid, f"Expected seq_id '{sid}', got '{record['seq_id']}'."

        assert math.isclose(record["analytical_M50"], wanted["analytical_M50"], rel_tol=1e-3, abs_tol=1e-3), \
            f"Record '{sid}' analytical_M50 expected ~{wanted['analytical_M50']}, got {record['analytical_M50']}"
        assert math.isclose(record["numerical_M50"], wanted["numerical_M50"], rel_tol=1e-3, abs_tol=1e-3), \
            f"Record '{sid}' numerical_M50 expected ~{wanted['numerical_M50']}, got {record['numerical_M50']}"
        assert math.isclose(record["numerical_derivative_M50"], wanted["numerical_derivative_M50"], rel_tol=1e-3, abs_tol=1e-3), \
            f"Record '{sid}' numerical_derivative_M50 expected ~{wanted['numerical_derivative_M50']}, got {record['numerical_derivative_M50']}"
        assert record["passed_regression"] == wanted["passed_regression"], \
            f"Record '{sid}' passed_regression expected {wanted['passed_regression']}, got {record['passed_regression']}"


def test_regression_script_and_report():
    assert os.path.exists(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist."
    assert stat.S_ISREG(os.lstat(SCRIPT_PATH).st_mode), f"File {SCRIPT_PATH} must be a regular file."

    original_seqs = [
        ("seq1", "ATGCGTAACGTACGTAGCTAGCTAGCATCGATCGATCGATCGA"),
        ("seq2", "GGGGCCCCGGGGCCCCGGGGCCCC"),
        ("seq3", "ATATATATATATATATATATATATATATATAT"),
    ]

    rng = random.SystemRandom()
    suffix = "".join(rng.choice(string.ascii_lowercase + string.digits) for _ in range(12))

    def shuffled_sequence(counts):
        bases = []
        for base, count in counts.items():
            bases.extend(base * count)
        rng.shuffle(bases)
        return "".join(bases)

    dynamic_seqs = [
        ("balanced_" + suffix, shuffled_sequence({"A": 11, "T": 10, "G": 12, "C": 9})),
        ("gc_rich_" + suffix, shuffled_sequence({"A": 3, "T": 4, "G": 29, "C": 23})),
        ("at_rich_" + suffix, shuffled_sequence({"A": 31, "T": 27, "G": 4, "C": 2})),
        ("random_" + suffix, "".join(rng.choice("ACGT") for _ in range(rng.randint(25, 85)))),
    ]

    try:
        # Retain the original verifier's checks, but require the submitted script
        # to generate the report rather than accepting a prewritten JSON file.
        write_fasta(original_seqs)
        run_submission()
        check_report(original_seqs)

        # Exercise the same artifact on unpredictable FASTA contents so fixed
        # hardcoded records cannot satisfy the verifier.
        write_fasta(dynamic_seqs)
        run_submission()
        check_report(dynamic_seqs)
    finally:
        write_fasta(original_seqs)

    # Leave the requested report corresponding to the provided FASTA file.
    run_submission()
    check_report(original_seqs)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
