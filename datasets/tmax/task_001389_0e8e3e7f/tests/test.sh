#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import secrets
import stat
import subprocess

import pytest

PROJECT = "/home/user/csv_processor"
SOURCE = os.path.join(PROJECT, "main.go")
INPUT = os.path.join(PROJECT, "dataset.csv")
OUTPUT = os.path.join(PROJECT, "processed.csv")
BINARY = "/tmp/csv_processor_submission"


def run_processor():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [BINARY], cwd=PROJECT, text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, (
        f"Processor failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def build_and_run_submission():
    assert os.path.exists(SOURCE), f"Required source file {SOURCE} does not exist."
    source_stat = os.lstat(SOURCE)
    assert stat.S_ISREG(source_stat.st_mode), f"{SOURCE} must be a regular Go source file."
    assert source_stat.st_size > 0, f"{SOURCE} is empty."

    build = subprocess.run(
        ["go", "build", "-o", BINARY, "main.go"],
        cwd=PROJECT,
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert build.returncode == 0, (
        f"main.go did not build successfully.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )
    assert os.path.isfile(BINARY), "Building main.go did not produce an executable."

    # Remove any agent-created output and regenerate it by executing the submitted code.
    run_processor()


def test_processed_csv_exists():
    processed_path = "/home/user/csv_processor/processed.csv"
    assert os.path.isfile(processed_path), f"Output file {processed_path} was not created."


def test_processed_csv_contents():
    input_path = "/home/user/csv_processor/dataset.csv"
    processed_path = "/home/user/csv_processor/processed.csv"

    # Read input to compute expected truth
    with open(input_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        input_rows = list(reader)

    train_rows = [r for r in input_rows if r['Split'] == 'train']

    # Compute mean
    n_train = len(train_rows)
    assert n_train > 1, "Need at least 2 train rows for sample stddev."

    mean_f1 = sum(float(r['F1']) for r in train_rows) / n_train
    mean_f2 = sum(float(r['F2']) for r in train_rows) / n_train
    mean_f3 = sum(float(r['F3']) for r in train_rows) / n_train

    # Compute sample stddev
    sq_diff_f1 = sum((float(r['F1']) - mean_f1) ** 2 for r in train_rows)
    sq_diff_f2 = sum((float(r['F2']) - mean_f2) ** 2 for r in train_rows)
    sq_diff_f3 = sum((float(r['F3']) - mean_f3) ** 2 for r in train_rows)

    std_f1 = math.sqrt(sq_diff_f1 / (n_train - 1))
    std_f2 = math.sqrt(sq_diff_f2 / (n_train - 1))
    std_f3 = math.sqrt(sq_diff_f3 / (n_train - 1))

    expected_output = []
    for r in input_rows:
        expected_output.append({
            'ID': r['ID'],
            'F1': f"{(float(r['F1']) - mean_f1) / std_f1:.4f}",
            'F2': f"{(float(r['F2']) - mean_f2) / std_f2:.4f}",
            'F3': f"{(float(r['F3']) - mean_f3) / std_f3:.4f}",
            'Split': r['Split']
        })

    # Read processed output
    with open(processed_path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['ID', 'F1', 'F2', 'F3', 'Split'], f"Header is incorrect: {header}"

        output_rows = []
        for row in reader:
            output_rows.append({
                'ID': row[0],
                'F1': row[1],
                'F2': row[2],
                'F3': row[3],
                'Split': row[4]
            })

    assert len(output_rows) == len(expected_output), "Number of rows in processed.csv does not match dataset.csv."

    for i, (out_row, exp_row) in enumerate(zip(output_rows, expected_output)):
        assert out_row['ID'] == exp_row['ID'], f"Row {i+1} ID mismatch: expected {exp_row['ID']}, got {out_row['ID']}"
        assert out_row['Split'] == exp_row['Split'], f"Row {i+1} Split mismatch: expected {exp_row['Split']}, got {out_row['Split']}"
        assert out_row['F1'] == exp_row['F1'], f"Row {i+1} F1 mismatch: expected {exp_row['F1']}, got {out_row['F1']}"
        assert out_row['F2'] == exp_row['F2'], f"Row {i+1} F2 mismatch: expected {exp_row['F2']}, got {out_row['F2']}"
        assert out_row['F3'] == exp_row['F3'], f"Row {i+1} F3 mismatch: expected {exp_row['F3']}, got {out_row['F3']}"


def test_executable_uses_train_statistics_on_unseen_data():
    original_dataset = open(INPUT, "rb").read()
    original_output = open(OUTPUT, "rb").read() if os.path.exists(OUTPUT) else None

    rng = secrets.SystemRandom()
    a, b, c = (rng.randint(20, 500) for _ in range(3))
    rows = [
        ["901", str(a + 1200), str(b - 900), str(c + 1700), "test"],
        ["902", str(a + 1), str(b + 3), str(c + 8), "train"],
        ["903", str(a + 6), str(b + 11), str(c + 2), "train"],
        ["904", str(a - 700), str(b + 1300), str(c - 800), "test"],
        ["905", str(a + 14), str(b + 5), str(c + 17), "train"],
        ["906", str(a + 9), str(b + 19), str(c + 11), "train"],
        ["907", str(a + 2300), str(b + 2100), str(c + 900), "test"],
    ]

    try:
        with open(INPUT, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["ID", "F1", "F2", "F3", "Split"])
            writer.writerows(rows)

        run_processor()
        assert os.path.isfile(OUTPUT), "Executing the submitted program did not create processed.csv."

        train = [r for r in rows if r[4] == "train"]
        means = [sum(float(r[j]) for r in train) / len(train) for j in (1, 2, 3)]
        stds = [
            math.sqrt(sum((float(r[j]) - means[j - 1]) ** 2 for r in train) / (len(train) - 1))
            for j in (1, 2, 3)
        ]
        expected = [
            [r[0]] + [f"{(float(r[j]) - means[j - 1]) / stds[j - 1]:.4f}" for j in (1, 2, 3)] + [r[4]]
            for r in rows
        ]

        with open(OUTPUT, "r", newline="") as f:
            actual = list(csv.reader(f))

        assert actual, "processed.csv is empty."
        assert actual[0] == ["ID", "F1", "F2", "F3", "Split"], f"Header is incorrect: {actual[0]}"
        assert actual[1:] == expected, "Submitted program produced incorrect output for an unseen dataset."
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_dataset)
        if original_output is None:
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
