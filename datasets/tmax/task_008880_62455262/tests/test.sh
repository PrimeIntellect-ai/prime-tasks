#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re
import secrets
import subprocess
import py_compile
import pytest
import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

SCRIPT = "/home/user/validate_etl.py"
GOLDEN = "/home/user/golden_records.txt"
INCOMING = "/home/user/incoming_records.txt"
RESULTS = "/home/user/validation_results.csv"


def test_validation_results_exists():
    path = "/home/user/validation_results.csv"
    assert os.path.isfile(path), f"Missing file: {path}"


def test_validation_results_content():
    path = "/home/user/validation_results.csv"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "The validation_results.csv file is empty."
    assert rows[0] == ["record_id", "status", "max_similarity"], f"Incorrect CSV header: {rows[0]}"

    # Expected values based on the deterministic TF-IDF and cosine similarity calculations
    # using default parameters and the provided golden/incoming records.
    expected_rows = [
        ["0", "VALID", "0.1873"],
        ["1", "VALID", "0.0000"],
        ["2", "VALID", "0.2222"],
        ["3", "VALID", "0.0000"],
        ["4", "VALID", "0.3848"],
        ["5", "VALID", "0.0000"],
        ["6", "VALID", "0.3015"],
    ]

    assert len(rows) - 1 == len(expected_rows), f"Expected {len(expected_rows)} data rows, but found {len(rows) - 1}."

    for i, (actual, expected) in enumerate(zip(rows[1:], expected_rows)):
        assert len(actual) == 3, f"Row {i+1} does not have exactly 3 columns: {actual}"
        assert actual[0] == expected[0], f"Row {i+1}: expected record_id {expected[0]}, got {actual[0]}"
        assert actual[1] == expected[1], f"Row {i+1}: expected status {expected[1]}, got {actual[1]}"

        # Check similarity formatting and value
        try:
            actual_sim = float(actual[2])
            expected_sim = float(expected[2])
        except ValueError:
            pytest.fail(f"Row {i+1}: max_similarity '{actual[2]}' is not a valid float.")

        assert len(actual[2].split('.')[-1]) == 4, f"Row {i+1}: max_similarity '{actual[2]}' must be formatted to exactly 4 decimal places."

        # Allow a tiny margin of error in case of different architecture floating point math,
        # but string should match up to 4 decimals in most standard environments.
        assert abs(actual_sim - expected_sim) < 0.0002, f"Row {i+1}: expected max_similarity ~{expected[2]}, got {actual[2]}"


def compute_expected(golden_lines, incoming_lines):
    golden_records = [line.strip() for line in golden_lines if line.strip()]
    incoming_records = [line.strip() for line in incoming_lines if line.strip()]

    vectorizer = TfidfVectorizer()
    golden_vectors = vectorizer.fit_transform(golden_records)

    np.random.seed(42)
    pairs = np.random.choice(len(golden_records), size=(1000, 2), replace=True)
    scores = [
        cosine_similarity(golden_vectors[a], golden_vectors[b])[0, 0]
        for a, b in pairs
    ]
    threshold = np.percentile(scores, 5)

    incoming_vectors = vectorizer.transform(incoming_records)
    expected = []
    for record_id in range(len(incoming_records)):
        similarities = cosine_similarity(incoming_vectors[record_id], golden_vectors)[0]
        maximum = float(np.max(similarities))
        status = "INVALID" if maximum < threshold else "VALID"
        expected.append([str(record_id), status, f"{maximum:.4f}"])
    return threshold, expected


def run_case(golden_lines, incoming_lines):
    with open(GOLDEN, "w", encoding="utf-8") as f:
        f.write("\n".join(golden_lines) + "\n")
    with open(INCOMING, "w", encoding="utf-8") as f:
        f.write("\n".join(incoming_lines) + "\n")

    if os.path.exists(RESULTS):
        os.remove(RESULTS)

    completed = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"validate_etl.py failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULTS), "The script did not produce validation_results.csv"

    with open(RESULTS, newline="", encoding="utf-8") as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ["record_id", "status", "max_similarity"], (
        f"Incorrect CSV header after executing the script: {rows[0] if rows else None}"
    )
    for row in rows[1:]:
        assert len(row) == 3, f"Output row does not have exactly 3 columns: {row}"
        assert re.fullmatch(r"-?\d+\.\d{4}", row[2]), (
            f"max_similarity must have exactly four decimal places: {row[2]}"
        )
    return rows[1:]


def test_script_executes_algorithm_on_unseen_inputs():
    assert os.path.isfile(SCRIPT), f"Missing required script: {SCRIPT}"
    py_compile.compile(SCRIPT, doraise=True)

    paths = [GOLDEN, INCOMING, RESULTS]
    originals = {
        path: (open(path, "rb").read() if os.path.exists(path) else None)
        for path in paths
    }

    nonce = "n" + secrets.token_hex(10)
    try:
        # Shared vocabulary gives a positive bootstrap threshold, so an unrelated
        # incoming record must be INVALID. Blank lines also test filtering/indexing.
        common_a = "commonalpha" + nonce
        common_b = "commonbeta" + nonce
        golden_positive = [
            f"{common_a} {common_b} unique{i}{nonce}" for i in range(10)
        ]
        golden_positive.insert(3, "")
        golden_positive.insert(8, "   ")
        incoming_positive = [
            golden_positive[0],
            "",
            f"unrelatedword{nonce}",
            f"{common_a} {common_b}",
            "   ",
            f"{common_a} unique5{nonce}",
        ]
        threshold, expected = compute_expected(golden_positive, incoming_positive)
        assert threshold > 0
        actual = run_case(golden_positive, incoming_positive)
        assert actual == expected, f"Unexpected results for positive-threshold case: {actual} != {expected}"
        assert any(row[1] == "INVALID" for row in expected)

        # Mutually orthogonal golden records yield a zero 5th percentile. The
        # strict '< threshold' rule therefore marks a zero-similarity item VALID.
        golden_zero = [
            f"gold{i}{nonce} feature{i}{nonce}" for i in range(12)
        ]
        golden_zero.insert(1, "")
        incoming_zero = [
            f"outside{nonce}",
            " ",
            f"gold4{nonce} feature4{nonce}",
            f"anotheroutside{nonce}",
        ]
        threshold, expected = compute_expected(golden_zero, incoming_zero)
        assert threshold == 0
        actual = run_case(golden_zero, incoming_zero)
        assert actual == expected, f"Unexpected results for zero-threshold case: {actual} != {expected}"
        assert expected[0][1] == "VALID" and expected[0][2] == "0.0000"
    finally:
        for path, content in originals.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
