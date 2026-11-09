#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import secrets
import statistics
import string
import subprocess
import tempfile

EVIL_DIR = "/app/corpus/evil"
CLEAN_DIR = "/app/corpus/clean"
SCRIPT_PATH = "/home/user/etl_pipeline.py"
HEADERS = ["Alpha", "Beta", "Gamma"]
BOUNDS = [(-50.0, 50.0), (0.0, 100.0), (-10.0, 10.0)]


def run_pipeline(input_path, output_path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, "--input", input_path, "--output", output_path],
        capture_output=True,
        text=True,
        timeout=20,
    )


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_evil_corpus_rejected():
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.csv')]
    bypassed = []

    for evil_file in evil_files:
        input_path = os.path.join(EVIL_DIR, evil_file)
        with tempfile.NamedTemporaryFile(suffix='.csv') as tmp_out:
            result = subprocess.run(
                ["python", SCRIPT_PATH, "--input", input_path, "--output", tmp_out.name],
                capture_output=True
            )
            if result.returncode != 1:
                bypassed.append(evil_file)

    assert not bypassed, f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}"


def test_clean_corpus_accepted_and_sanitized():
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.csv')]
    modified = []

    for clean_file in clean_files:
        input_path = os.path.join(CLEAN_DIR, clean_file)
        with tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as tmp_out:
            output_path = tmp_out.name

        try:
            result = subprocess.run(
                ["python", SCRIPT_PATH, "--input", input_path, "--output", output_path],
                capture_output=True
            )
            if result.returncode != 0:
                modified.append(f"{clean_file} (exit code {result.returncode})")
                continue

            if not os.path.isfile(output_path) or os.path.getsize(output_path) == 0:
                modified.append(f"{clean_file} (output file missing or empty)")
                continue

            with open(output_path, 'r') as f:
                reader = csv.DictReader(f)
                for row_idx, row in enumerate(reader):
                    try:
                        alpha = float(row.get('Alpha', 0))
                        beta = float(row.get('Beta', 0))
                        gamma = float(row.get('Gamma', 0))

                        if not (-50.0 <= alpha <= 50.0):
                            modified.append(f"{clean_file} (Alpha out of bounds at row {row_idx})")
                            break
                        if not (0.0 <= beta <= 100.0):
                            modified.append(f"{clean_file} (Beta out of bounds at row {row_idx})")
                            break
                        if not (-10.0 <= gamma <= 10.0):
                            modified.append(f"{clean_file} (Gamma out of bounds at row {row_idx})")
                            break
                    except ValueError:
                        modified.append(f"{clean_file} (Non-float value found at row {row_idx})")
                        break
        finally:
            if os.path.exists(output_path):
                os.remove(output_path)

    assert not modified, f"{len(modified)} of {len(clean_files)} clean modified or failed: {', '.join(modified)}"


def expected_sanitized(columns):
    result_columns = []
    for values, (low, high) in zip(columns, BOUNDS):
        present = [float(value) for value in values if value is not None and str(value).lower() != "nan"]
        median = statistics.median(present)
        filled = [median if value is None or str(value).lower() == "nan" else float(value) for value in values]
        result_columns.append([min(high, max(low, value)) for value in filled])
    return [list(row) for row in zip(*result_columns)]


def test_generated_clean_inputs_are_fully_sanitized():
    rng = secrets.SystemRandom()

    for missing_token in (None, "NaN"):
        columns = [
            [rng.randint(-40, 40), missing_token, rng.randint(51, 450), rng.randint(-450, -51), rng.randint(-40, 40)],
            [rng.randint(0, 100), rng.randint(0, 100), missing_token, rng.randint(101, 900), rng.randint(-900, -1)],
            [missing_token, rng.randint(-9, 9), rng.randint(11, 90), rng.randint(-90, -11), rng.randint(-9, 9)],
        ]
        expected = expected_sanitized(columns)
        rows = list(zip(*columns))

        with tempfile.TemporaryDirectory() as td:
            input_path = os.path.join(td, secrets.token_hex(12) + ".csv")
            output_path = os.path.join(td, secrets.token_hex(12) + ".csv")
            with open(input_path, "w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(HEADERS)
                writer.writerows([["" if value is None else value for value in row] for row in rows])

            result = run_pipeline(input_path, output_path)
            assert result.returncode == 0, result.stderr
            assert os.path.isfile(output_path), "Accepted input did not produce an output CSV"

            with open(output_path, newline="") as f:
                output_rows = list(csv.reader(f))

            assert output_rows, "Output CSV is empty"
            assert output_rows[0] == HEADERS, "Output headers were not preserved exactly"
            assert len(output_rows) == len(expected) + 1, "Output row count differs from input row count"

            for row_index, (actual_row, expected_row) in enumerate(zip(output_rows[1:], expected)):
                assert len(actual_row) == 3, f"Output row {row_index} does not contain exactly three fields"
                actual = [float(value) for value in actual_row]
                assert all(math.isfinite(value) for value in actual), f"Non-finite value in output row {row_index}"
                for column_index, (actual_value, expected_value) in enumerate(zip(actual, expected_row)):
                    assert math.isclose(actual_value, expected_value, rel_tol=0.0, abs_tol=1e-9), (
                        f"Incorrect value at row {row_index}, column {HEADERS[column_index]}: "
                        f"expected {expected_value}, got {actual_value}"
                    )


def test_generated_adversarial_inputs_are_rejected_without_output():
    rng = secrets.SystemRandom()
    token = "BAD_" + ''.join(rng.choice(string.ascii_letters) for _ in range(18))
    evil_rows = [
        [500.0 + rng.randint(1, 5000), rng.randint(1, 99), rng.randint(-9, 9)],
        [rng.randint(-40, 40), 1000.0 + rng.randint(1, 5000), rng.randint(-9, 9)],
        [rng.randint(-40, 40), rng.randint(1, 99), -(100.0 + rng.randint(1, 5000))],
        [rng.randint(-40, 40), token, rng.randint(-9, 9)],
    ]

    for evil_row in evil_rows:
        with tempfile.TemporaryDirectory() as td:
            input_path = os.path.join(td, secrets.token_hex(12) + ".csv")
            output_path = os.path.join(td, secrets.token_hex(12) + ".csv")
            with open(input_path, "w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(HEADERS)
                writer.writerow(evil_row)

            assert not os.path.exists(output_path)
            result = run_pipeline(input_path, output_path)
            assert result.returncode == 1, f"Adversarial row was not rejected: {evil_row}"
            assert not os.path.exists(output_path), "Rejected input created an output file"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
