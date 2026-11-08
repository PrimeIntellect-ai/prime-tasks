#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile

import pytest

EXECUTABLE = "/home/user/etl_processor"
SOURCE = "/home/user/etl_processor.c"
DATASET = "/home/user/dataset.csv"
PROCESSED = "/home/user/processed.csv"

EXPECTED_LINES = [
    "1,200",
    "2,NA",
    "3,NA",
    "4,NA",
    "5,56",
    "6,0",
]


def run_processor(path, rows):
    input_text = "\n".join(",".join(row) for row in rows) + "\n"
    result = subprocess.run(
        [path],
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}. stderr: {result.stderr}"
    )
    return result.stdout.splitlines()


def expected_for(rows):
    output = []
    for row_id, val1, val2 in rows:
        product = "NA" if val1 == "NA" or val2 == "NA" else str(int(val1) * int(val2))
        output.append(f"{row_id},{product}")
    return output


def challenge_rows():
    rows = [
        ("edge-negative", "-12", "7"),
        ("edge-left-na", "NA", "-9"),
        ("edge-right-na", "14", "NA"),
        ("edge-both-na", "NA", "NA"),
        ("edge-zero", "0", "-123"),
        ("edge-positive-sign", "+11", "3"),
    ]
    rng = random.SystemRandom()
    for i in range(30):
        val1 = "NA" if rng.randrange(5) == 0 else str(rng.randint(-10000, 10000))
        val2 = "NA" if rng.randrange(5) == 0 else str(rng.randint(-10000, 10000))
        rows.append((f"random-{i}-{rng.randrange(1 << 30)}", val1, val2))
    return rows


def test_executable_exists():
    path = EXECUTABLE
    assert os.path.isfile(path), f"Executable {path} does not exist. Did you compile the C program?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_processed_csv_exists():
    path = PROCESSED
    assert os.path.isfile(path), f"Output file {path} does not exist. Did you run the pipeline and save the output?"


def test_processed_csv_content():
    path = PROCESSED
    assert os.path.isfile(path), f"Output file {path} does not exist."

    with open(path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(EXPECTED_LINES), f"Expected {len(EXPECTED_LINES)} lines in {path}, but found {len(actual_lines)}. Did you skip the header correctly?"

    for i, (actual, expected) in enumerate(zip(actual_lines, EXPECTED_LINES)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'."


def test_submitted_executable_processes_dataset():
    with open(DATASET, "r") as f:
        lines = [line.rstrip("\n") for line in f]
    assert lines and lines[0] == "id,val1,val2"
    rows = [tuple(line.split(",")) for line in lines[1:]]
    assert run_processor(EXECUTABLE, rows) == EXPECTED_LINES


def test_source_and_executable_on_unseen_inputs():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    rows = challenge_rows()
    expected = expected_for(rows)

    assert run_processor(EXECUTABLE, rows) == expected, (
        "The submitted executable does not correctly propagate NA values and multiply valid integers."
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "etl_processor")
        compile_result = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert compile_result.returncode == 0, (
            f"The modified source does not compile with gcc: {compile_result.stderr}"
        )
        assert run_processor(rebuilt, rows) == expected, (
            "A fresh build of etl_processor.c does not correctly propagate NA values and multiply valid integers."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
