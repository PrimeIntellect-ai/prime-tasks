#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import hashlib
import secrets
import subprocess
import pytest

PROJECT_DIR = "/home/user/pipeline"
SOURCE_RS = "/home/user/pipeline/src/main.rs"
OUTPUT_CSV = "/home/user/pipeline/output.csv"
INPUT_CSV = "/home/user/data/input.csv"
HASH_TXT = "/home/user/pipeline/artifact_hash.txt"
BINARY = "/home/user/pipeline/target/debug/pipeline"


def expected_rows(data):
    n = len(data)
    assert n > 0, "Input data is empty."
    mean = sum(value for _, value in data) / n
    variance = sum((value - mean) ** 2 for _, value in data) / n
    std_dev = math.sqrt(variance)
    return [(row_id, value, f"{(value - mean) / std_dev:.4f}") for row_id, value in data]


def assert_output_matches(data):
    assert os.path.isfile(OUTPUT_CSV), f"Output file {OUTPUT_CSV} is missing."
    with open(OUTPUT_CSV, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["id", "sensor_value", "z_score"], f"Output CSV header is incorrect: {header}"
        rows = list(reader)

    expected = expected_rows(data)
    assert len(rows) == len(expected), f"Output CSV has {len(rows)} rows, expected {len(expected)}."
    for i, ((expected_id, expected_value, expected_z), row) in enumerate(zip(expected, rows)):
        assert len(row) == 3, f"Row {i+1}: expected exactly 3 columns, got {len(row)}"
        out_id, out_value, out_z = row
        assert out_id == expected_id, f"Row {i+1}: expected id {expected_id}, got {out_id}"
        assert float(out_value) == expected_value, f"Row {i+1}: expected sensor_value {expected_value}, got {out_value}"
        assert out_z == expected_z, f"Row {i+1}: expected z_score {expected_z}, got {out_z}"
        assert len(out_z.split(".")[-1]) == 4, f"Row {i+1}: z_score {out_z} does not have exactly 4 decimal places."


@pytest.fixture(scope="session", autouse=True)
def build_and_execute_pipeline():
    assert os.path.isfile(SOURCE_RS), f"Rust source file {SOURCE_RS} is missing."
    subprocess.run(["cargo", "build"], cwd=PROJECT_DIR, check=True, timeout=120)
    assert os.path.isfile(BINARY), f"Expected built pipeline binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Built pipeline artifact {BINARY} is not executable."

    with open(INPUT_CSV, "rb") as f:
        original_input = f.read()

    rng = secrets.SystemRandom()
    base = rng.randrange(4_000_000_000_000, 8_000_000_000_000)
    offsets = sorted(rng.sample(range(0, 10001), 9))
    hidden_data = [(f"hidden-{i+1}", float(base + offset)) for i, offset in enumerate(offsets)]

    hidden_error = None
    try:
        with open(INPUT_CSV, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["id", "sensor_value"])
            for row_id, value in hidden_data:
                writer.writerow([row_id, f"{value:.1f}"])

        subprocess.run([BINARY], cwd=PROJECT_DIR, check=True, timeout=30)
        assert_output_matches(hidden_data)
    except BaseException as exc:
        hidden_error = exc
    finally:
        with open(INPUT_CSV, "wb") as f:
            f.write(original_input)
        subprocess.run([BINARY], cwd=PROJECT_DIR, check=True, timeout=30)

    if hidden_error is not None:
        raise hidden_error


def test_output_csv_exists():
    assert os.path.isfile(OUTPUT_CSV), f"Expected output file {OUTPUT_CSV} does not exist."


def test_output_csv_content():
    assert os.path.isfile(INPUT_CSV), f"Input file {INPUT_CSV} is missing."

    input_data = []
    with open(INPUT_CSV, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            input_data.append((row["id"], float(row["sensor_value"])))

    n = len(input_data)
    assert n > 0, "Input data is empty."
    mean = sum(val for _, val in input_data) / n
    variance = sum((val - mean) ** 2 for _, val in input_data) / n
    std_dev = math.sqrt(variance)

    assert os.path.isfile(OUTPUT_CSV), f"Output file {OUTPUT_CSV} is missing."
    with open(OUTPUT_CSV, "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["id", "sensor_value", "z_score"], f"Output CSV header is incorrect: {header}"
        output_rows = list(reader)

    assert len(output_rows) == n, f"Output CSV has {len(output_rows)} rows, expected {n}."

    for i, (expected_id, expected_val) in enumerate(input_data):
        out_id, out_val, out_z = output_rows[i]
        assert out_id == expected_id, f"Row {i+1}: expected id {expected_id}, got {out_id}"
        assert float(out_val) == expected_val, f"Row {i+1}: expected sensor_value {expected_val}, got {out_val}"

        expected_z = (expected_val - mean) / std_dev
        expected_z_str = f"{expected_z:.4f}"

        assert out_z == expected_z_str, f"Row {i+1}: expected z_score {expected_z_str}, got {out_z}"
        assert len(out_z.split(".")[-1]) == 4, f"Row {i+1}: z_score {out_z} does not have exactly 4 decimal places."


def test_artifact_hash_exists_and_correct():
    assert os.path.isfile(OUTPUT_CSV), f"Output file {OUTPUT_CSV} is missing."
    assert os.path.isfile(HASH_TXT), f"Hash file {HASH_TXT} does not exist."

    with open(OUTPUT_CSV, "rb") as f:
        output_bytes = f.read()

    expected_hash = hashlib.sha256(output_bytes).hexdigest()

    with open(HASH_TXT, "r") as f:
        actual_hash_content = f.read().strip()

    actual_hash = actual_hash_content.split()[0] if actual_hash_content else ""
    assert actual_hash == expected_hash, f"Hash mismatch. Expected {expected_hash}, got {actual_hash}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
