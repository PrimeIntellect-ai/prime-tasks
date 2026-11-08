#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import stat
import subprocess

INPUT_CSV = "/home/user/data/input.csv"
TRAIN_CSV = "/home/user/data/train_normalized.csv"
TEST_CSV = "/home/user/data/test_normalized.csv"
PROJECT_DIR = "/home/user/pipeline"
SOURCE_FILE = "/home/user/pipeline/src/main.rs"
MANIFEST_FILE = "/home/user/pipeline/Cargo.toml"
BINARY_FILE = "/home/user/pipeline/target/release/pipeline"


def test_output_files_exist():
    assert os.path.isfile(TRAIN_CSV), "The file /home/user/data/train_normalized.csv was not created."
    assert os.path.isfile(TEST_CSV), "The file /home/user/data/test_normalized.csv was not created."


def test_normalized_data_correctness():
    # Read input data
    with open(INPUT_CSV, "r") as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 101, "Input file should have 101 lines (1 header + 100 data rows)."

    header = lines[0]
    data_lines = lines[1:]
    assert header == "id,category,value", "Input CSV header is incorrect."

    # Extract complete input rows
    input_rows = []
    values = []
    for line in data_lines:
        parts = line.split(',')
        assert len(parts) == 3, f"Malformed input line: {line}"
        input_rows.append(parts)
        values.append(float(parts[2]))

    # Calculate training parameters (first 80 rows)
    train_values = values[:80]
    train_mean = sum(train_values) / len(train_values)
    train_variance = sum((x - train_mean) ** 2 for x in train_values) / len(train_values)
    train_std_dev = math.sqrt(train_variance)

    # Read train_normalized.csv
    with open(TRAIN_CSV, "r") as f:
        train_out_lines = f.read().strip().split('\n')

    assert train_out_lines[0] == "id,category,normalized_value", "Header in train_normalized.csv is incorrect."
    assert len(train_out_lines) == 81, f"Expected 81 lines in train_normalized.csv, found {len(train_out_lines)}."

    for i in range(80):
        expected_norm = (values[i] - train_mean) / train_std_dev
        expected_str = f"{expected_norm:.4f}"

        out_parts = train_out_lines[i + 1].split(',')
        assert len(out_parts) == 3, f"Malformed line in train_normalized.csv: {train_out_lines[i + 1]}"
        assert out_parts[0] == input_rows[i][0], f"Row {i + 1} in train_normalized.csv has the wrong id."
        assert out_parts[1] == input_rows[i][1], f"Row {i + 1} in train_normalized.csv has the wrong category."
        assert out_parts[2] == expected_str, f"Row {i + 1} in train_normalized.csv has wrong normalized value. Expected {expected_str}, got {out_parts[2]}. This indicates data leakage or incorrect calculation."

    # Read test_normalized.csv
    with open(TEST_CSV, "r") as f:
        test_out_lines = f.read().strip().split('\n')

    assert test_out_lines[0] == "id,category,normalized_value", "Header in test_normalized.csv is incorrect."
    assert len(test_out_lines) == 21, f"Expected 21 lines in test_normalized.csv, found {len(test_out_lines)}."

    for i in range(20):
        idx = i + 80
        expected_norm = (values[idx] - train_mean) / train_std_dev
        expected_str = f"{expected_norm:.4f}"

        out_parts = test_out_lines[i + 1].split(',')
        assert len(out_parts) == 3, f"Malformed line in test_normalized.csv: {test_out_lines[i + 1]}"
        assert out_parts[0] == input_rows[idx][0], f"Row {i + 1} in test_normalized.csv has the wrong id."
        assert out_parts[1] == input_rows[idx][1], f"Row {i + 1} in test_normalized.csv has the wrong category."
        assert out_parts[2] == expected_str, f"Row {i + 1} in test_normalized.csv has wrong normalized value. Expected {expected_str}, got {out_parts[2]}. This indicates data leakage or incorrect calculation."


def validate_generated_outputs(rows):
    train_values = [row[2] for row in rows[:80]]
    mean = sum(train_values) / len(train_values)
    variance = sum((value - mean) ** 2 for value in train_values) / len(train_values)
    std_dev = math.sqrt(variance)

    for path, expected_rows in ((TRAIN_CSV, rows[:80]), (TEST_CSV, rows[80:])):
        with open(path, newline="") as f:
            output = list(csv.reader(f))

        assert output[0] == ["id", "category", "normalized_value"], f"Incorrect header in {path}."
        assert len(output) == len(expected_rows) + 1, f"Incorrect row count in {path}."

        offset = 0 if path == TRAIN_CSV else 80
        for position, (actual, expected) in enumerate(zip(output[1:], expected_rows)):
            assert len(actual) == 3, f"Malformed output row in {path}: {actual}"
            expected_norm = f"{(expected[2] - mean) / std_dev:.4f}"
            assert actual[0] == expected[0], f"Wrong id at input row {offset + position + 1}."
            assert actual[1] == expected[1], f"Wrong category at input row {offset + position + 1}."
            assert actual[2] == expected_norm, f"Wrong normalized value at input row {offset + position + 1}: expected {expected_norm}, got {actual[2]}."


def test_rust_source_was_built_and_binary_performs_pipeline():
    assert os.path.isfile(SOURCE_FILE), "The required Rust source file is missing."
    assert os.path.isfile(MANIFEST_FILE), "Cargo.toml is missing."
    assert os.path.isfile(BINARY_FILE), "The release binary was not built."
    assert os.access(BINARY_FILE, os.X_OK), "The release binary is not executable."
    assert stat.S_ISREG(os.stat(BINARY_FILE).st_mode), "The release artifact is not a regular file."
    with open(BINARY_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The release artifact is not a compiled ELF binary."
    assert os.path.getmtime(BINARY_FILE) >= os.path.getmtime(SOURCE_FILE), "The release binary is older than src/main.rs; run cargo build --release after fixing it."
    assert os.path.getmtime(BINARY_FILE) >= os.path.getmtime(MANIFEST_FILE), "The release binary is older than Cargo.toml; run cargo build --release."

    # Confirm the submitted Rust project builds. Cargo also ensures the binary used
    # below corresponds to the submitted source rather than an unrelated artifact.
    subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT_DIR,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    with open(INPUT_CSV, "rb") as f:
        original_input = f.read()
    original_train = open(TRAIN_CSV, "rb").read() if os.path.exists(TRAIN_CSV) else None
    original_test = open(TEST_CSV, "rb").read() if os.path.exists(TEST_CSV) else None

    # Nonlinear values and distinct identifiers ensure the executable itself must
    # preserve rows, split chronologically, and use training-only statistics.
    rows = []
    for i in range(100):
        if i < 80:
            value = float(((i * 37) % 113) - 41 + (i % 4) * 0.25)
        else:
            value = float(700 + i * i * 1.75)
        rows.append((f"probe_{1000 + i}", f"group_{(i * 3) % 7}", value))

    try:
        with open(INPUT_CSV, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["id", "category", "value"])
            writer.writerows(rows)

        for path in (TRAIN_CSV, TEST_CSV):
            if os.path.exists(path):
                os.remove(path)

        subprocess.run([BINARY_FILE], cwd=PROJECT_DIR, check=True, timeout=30)
        validate_generated_outputs(rows)
    finally:
        with open(INPUT_CSV, "wb") as f:
            f.write(original_input)
        try:
            subprocess.run([BINARY_FILE], cwd=PROJECT_DIR, check=True, timeout=30)
        except Exception:
            if original_train is not None:
                with open(TRAIN_CSV, "wb") as f:
                    f.write(original_train)
            if original_test is not None:
                with open(TEST_CSV, "wb") as f:
                    f.write(original_test)
            raise
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
