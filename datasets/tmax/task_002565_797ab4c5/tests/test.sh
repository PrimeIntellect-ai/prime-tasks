#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess
from collections import Counter
from decimal import Decimal
from pathlib import Path

import pytest

VALIDATE = Path("/home/user/validate.go")
PREDICTIONS = Path("/home/user/predictions.csv")
TRUTH = Path("/home/user/truth.csv")
OUTPUT = Path("/home/user/cleaned_metrics.csv")

EXPECTED_ORIGINAL = [
    ["id", "category", "abs_error"],
    ["1", "A", "0.50"],
    ["3", "A", "1.80"],
    ["5", "B", "0.10"],
    ["6", "C", "0.00"],
]


def read_csv(path):
    with path.open("r", newline="") as f:
        return list(csv.reader(f))


def assert_original_output():
    assert OUTPUT.is_file(), f"Expected output file {OUTPUT} does not exist."
    actual_data = read_csv(OUTPUT)

    assert len(actual_data) > 0, "The cleaned_metrics.csv file is empty."
    assert actual_data[0] == EXPECTED_ORIGINAL[0], (
        f"Header mismatch. Expected {EXPECTED_ORIGINAL[0]}, got {actual_data[0]}"
    )

    expected_rows = sorted(EXPECTED_ORIGINAL[1:], key=lambda x: int(x[0]))
    actual_rows = sorted(
        actual_data[1:], key=lambda x: int(x[0]) if x and x[0].isdigit() else 0
    )
    assert len(actual_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} rows, but got {len(actual_rows)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, (
            f"Row {i + 1} mismatch. Expected {expected}, got {actual}."
        )


def run_program():
    result = subprocess.run(
        ["go", "run", str(VALIDATE)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"go run failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert OUTPUT.is_file(), "Go program did not produce cleaned_metrics.csv."


def write_csv(path, rows):
    with path.open("w", newline="") as f:
        csv.writer(f).writerows(rows)


def cents_string(cents):
    sign = "-" if cents < 0 else ""
    cents = abs(cents)
    return f"{sign}{cents // 100}.{cents % 100:02d}"


def expected_rows(prediction_rows, truth_rows):
    truth_by_id = {
        row[0]: (Decimal(row[1]), row[2]) for row in truth_rows[1:]
    }
    expected = []
    for row in prediction_rows[1:]:
        record_id, prediction_text = row
        prediction = Decimal(prediction_text)
        if Decimal("0.0") <= prediction <= Decimal("100.0") and record_id in truth_by_id:
            actual, category = truth_by_id[record_id]
            error = abs(prediction - actual)
            expected.append((record_id, category, f"{error:.2f}"))
    return expected


def assert_dynamic_output(expected):
    data = read_csv(OUTPUT)
    assert data, "cleaned_metrics.csv is empty."
    assert data[0] == ["id", "category", "abs_error"], (
        f"Header mismatch: got {data[0]}"
    )
    assert all(len(row) == 3 for row in data[1:]), (
        f"Every output row must have exactly three fields: {data[1:]}"
    )
    actual = [tuple(row) for row in data[1:]]
    assert Counter(actual) == Counter(expected), (
        f"Output rows mismatch. Expected {expected}, got {actual}"
    )


def test_validate_go_exists():
    assert os.path.isfile(VALIDATE), f"Expected Go script {VALIDATE} does not exist."


def test_cleaned_metrics_csv():
    assert_original_output()


def test_go_program_executes_and_handles_changed_inputs():
    original_predictions = PREDICTIONS.read_bytes()
    original_truth = TRUTH.read_bytes()
    original_output = OUTPUT.read_bytes()
    rng = secrets.SystemRandom()

    try:
        # Execute the submitted program on the supplied dataset as well as checking
        # the output that the agent produced before verification.
        OUTPUT.unlink()
        run_program()
        assert_original_output()

        # Use fresh, unpredictable IDs and values so a fixed output cannot pass.
        for _ in range(3):
            base = rng.randrange(100000, 900000) * 20
            ids = [str(base + i) for i in range(1, 9)]
            token = secrets.token_hex(3)

            truth_rows = [["id", "actual_value", "category"]]
            for i in range(7):
                actual_cents = rng.randrange(-5000, 15001)
                truth_rows.append([
                    ids[i],
                    cents_string(actual_cents),
                    f"C{token}_{i}",
                ])

            prediction_rows = [
                ["id", "predicted_value"],
                [ids[0], "0.0"],                 # inclusive lower boundary
                [ids[1], "100.0"],               # inclusive upper boundary
                [ids[2], cents_string(rng.randrange(1, 10000))],
                [ids[3], "-0.01"],               # invalid below range
                [ids[4], "100.01"],              # invalid above range
                [ids[5], cents_string(rng.randrange(1, 10000))],
                [ids[7], cents_string(rng.randrange(1, 10000))], # no truth row
            ]

            rng.shuffle(truth_rows[1:])
            rng.shuffle(prediction_rows[1:])
            expected = expected_rows(prediction_rows, truth_rows)

            write_csv(PREDICTIONS, prediction_rows)
            write_csv(TRUTH, truth_rows)
            if OUTPUT.exists():
                OUTPUT.unlink()
            run_program()
            assert_dynamic_output(expected)
    finally:
        PREDICTIONS.write_bytes(original_predictions)
        TRUTH.write_bytes(original_truth)
        OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
