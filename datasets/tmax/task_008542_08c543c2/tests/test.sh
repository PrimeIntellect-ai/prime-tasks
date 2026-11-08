#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess

DATASET = "/home/user/dataset.csv"
SOURCE = "/home/user/data_processor.cpp"
PROCESS = "/home/user/process"
TRAIN_OUT = "/home/user/train_clean.csv"
TEST_OUT = "/home/user/test_clean.csv"
DECIMAL_4 = re.compile(r"^-?\d+\.\d{4}$")


def read_dataset(path):
    rows = []
    with open(path, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["id", "category", "measurement"]
        for row in reader:
            rows.append({
                "id": int(row["id"]),
                "category": row["category"],
                "measurement": float(row["measurement"]),
            })
    return rows


def read_output(path, expected_count):
    assert os.path.isfile(path), f"Missing output file: {path}"
    with open(path, "r", newline="") as f:
        lines = f.read().splitlines()

    assert lines, f"Empty output file: {path}"
    assert lines[0] == "id,category,measurement", f"Wrong header in {path}"
    assert len(lines) == expected_count + 1, \
        f"Expected {expected_count} rows in {path}, got {len(lines) - 1}"

    for line_number, line in enumerate(lines[1:], 2):
        fields = line.split(",")
        assert len(fields) == 3, f"Malformed CSV row {line_number} in {path}"
        assert DECIMAL_4.fullmatch(fields[2]), \
            f"Measurement on row {line_number} of {path} is not printed to exactly 4 decimal places: {fields[2]!r}"

    rows = []
    with open(path, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append({
                "id": int(row["id"]),
                "category": row["category"],
                "measurement": float(row["measurement"]),
            })
    assert len(rows) == expected_count
    return rows


def validate_outputs(original_data):
    assert len(original_data) == 1000, "Original dataset should have 1000 rows"

    train_data = original_data[:800]
    test_data = original_data[800:]
    valid_train_measurements = [
        row["measurement"] for row in train_data
        if row["measurement"] != -999.0
    ]
    assert valid_train_measurements

    train_mean = sum(valid_train_measurements) / len(valid_train_measurements)
    train_variance = sum(
        (x - train_mean) ** 2 for x in valid_train_measurements
    ) / len(valid_train_measurements)
    train_std = math.sqrt(train_variance)
    assert train_std > 0

    test_clean = read_output(TEST_OUT, 200)
    for orig, clean in zip(test_data, test_clean):
        assert orig["id"] == clean["id"], "ID mismatch in test output"
        assert orig["category"] == clean["category"], "Category mismatch in test output"
        val = train_mean if orig["measurement"] == -999.0 else orig["measurement"]
        expected_norm_rounded = round((val - train_mean) / train_std, 4)
        assert abs(clean["measurement"] - expected_norm_rounded) <= 0.0001, \
            f"Row ID {orig['id']}: expected normalized value ~{expected_norm_rounded}, got {clean['measurement']}"

    train_clean = read_output(TRAIN_OUT, 800)
    for orig, clean in zip(train_data, train_clean):
        assert orig["id"] == clean["id"], "ID mismatch in train output"
        assert orig["category"] == clean["category"], "Category mismatch in train output"
        val = train_mean if orig["measurement"] == -999.0 else orig["measurement"]
        expected_norm_rounded = round((val - train_mean) / train_std, 4)
        assert abs(clean["measurement"] - expected_norm_rounded) <= 0.0001, \
            f"Row ID {orig['id']}: expected normalized value ~{expected_norm_rounded}, got {clean['measurement']}"


def run_and_validate(executable, expected_data):
    for path in (TRAIN_OUT, TEST_OUT):
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run(
        [executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=20
    )
    assert result.returncode == 0, \
        f"{executable} failed with code {result.returncode}: {result.stderr}"
    validate_outputs(expected_data)


def make_dynamic_dataset():
    rows = []
    lines = ["id,category,measurement"]
    for i in range(1, 1001):
        category = ("A", "B", "C")[(i * 7) % 3]
        if i <= 800:
            missing = (i % 13 == 0)
            value = 20.0 + ((i * 37) % 101) / 10.0
        else:
            missing = (i % 17 == 0)
            value = 80.0 + ((i * 29) % 137) / 10.0
        text = "-999.0" if missing else f"{value:.1f}"
        numeric = -999.0 if missing else value
        lines.append(f"{i},{category},{text}")
        rows.append({"id": i, "category": category, "measurement": numeric})
    return ("\n".join(lines) + "\n").encode(), rows


def test_final_state():
    assert os.path.isfile(DATASET), f"Missing dataset file: {DATASET}"
    assert os.path.isfile(SOURCE), f"Missing C++ source file: {SOURCE}"
    assert os.path.isfile(PROCESS), f"Missing executable: {PROCESS}"
    assert os.access(PROCESS, os.X_OK), f"Executable bit is not set on {PROCESS}"
    with open(PROCESS, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{PROCESS} is not a compiled ELF executable"

    rebuilt = "/tmp/verifier_source_process"
    compile_result = subprocess.run(
        ["g++", "-O3", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, \
        f"The submitted C++ source does not compile: {compile_result.stderr}"

    with open(DATASET, "rb") as f:
        original_bytes = f.read()
    original_data = read_dataset(DATASET)
    assert len(original_data) == 1000, "Original dataset should have 1000 rows"
    dynamic_bytes, dynamic_data = make_dynamic_dataset()

    try:
        with open(DATASET, "wb") as f:
            f.write(dynamic_bytes)
        run_and_validate(PROCESS, dynamic_data)
        run_and_validate(rebuilt, dynamic_data)
    finally:
        with open(DATASET, "wb") as f:
            f.write(original_bytes)

    # Regenerate and check the requested final artifacts using the submitted executable.
    run_and_validate(PROCESS, original_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
