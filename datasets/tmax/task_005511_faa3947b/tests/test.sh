#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import subprocess

import pytest

DATA_DIR = "/home/user/data"
SCRIPT_PATH = "/home/user/process_etl.sh"
TRAIN_PATH = os.path.join(DATA_DIR, "train.csv")
TEST_PATH = os.path.join(DATA_DIR, "test.csv")
META_PATH = os.path.join(DATA_DIR, "meta.csv")
TRAIN_FINAL_PATH = os.path.join(DATA_DIR, "train_final.csv")
TEST_FINAL_PATH = os.path.join(DATA_DIR, "test_final.csv")


def write_file(path, content):
    with open(path, "w", newline="") as f:
        f.write(content)


def remove_outputs():
    for path in (TRAIN_FINAL_PATH, TEST_FINAL_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_script():
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Script failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def derive_expected(input_path, meta_path, train_path):
    with open(train_path, newline="") as f:
        train_rows = list(csv.DictReader(f))
    observed = [float(row["reading"]) for row in train_rows if row["reading"] != ""]
    train_mean = sum(observed) / len(observed)

    with open(meta_path, newline="") as f:
        factors = {int(row["id"]): float(row["factor"]) for row in csv.DictReader(f)}

    def adjusted(row):
        reading = train_mean if row["reading"] == "" else float(row["reading"])
        return reading * factors[int(row["id"])]

    train_adjusted = [adjusted(row) for row in train_rows]
    train_min = min(train_adjusted)
    train_max = max(train_adjusted)

    with open(input_path, newline="") as f:
        rows = list(csv.DictReader(f))

    expected = ["id,scaled_adjusted_reading"]
    for row in sorted(rows, key=lambda item: int(item["id"])):
        scaled = (adjusted(row) - train_min) / (train_max - train_min)
        expected.append(f'{int(row["id"])},{scaled:.4f}')
    return expected


@pytest.fixture(scope="module")
def canonical_run():
    write_file(TRAIN_PATH, "id,reading\n1,10.0\n2,20.0\n3,\n4,30.0\n")
    write_file(TEST_PATH, "id,reading\n5,\n6,50.0\n7,60.0\n")
    write_file(META_PATH, "id,factor\n1,1.5\n2,2.0\n3,1.0\n4,0.5\n5,2.0\n6,1.0\n7,0.5\n")
    remove_outputs()
    run_script()


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_train_final_content(canonical_run):
    assert os.path.isfile(TRAIN_FINAL_PATH), f"Output file {TRAIN_FINAL_PATH} was not created."

    lines = read_nonempty_lines(TRAIN_FINAL_PATH)
    expected_lines = [
        "id,scaled_adjusted_reading",
        "1,0.0000",
        "2,1.0000",
        "3,0.2000",
        "4,0.0000"
    ]

    assert lines == expected_lines, f"Content of {TRAIN_FINAL_PATH} is incorrect. Expected {expected_lines}, got {lines}."


def test_test_final_content(canonical_run):
    assert os.path.isfile(TEST_FINAL_PATH), f"Output file {TEST_FINAL_PATH} was not created."

    lines = read_nonempty_lines(TEST_FINAL_PATH)
    expected_lines = [
        "id,scaled_adjusted_reading",
        "5,1.0000",
        "6,1.4000",
        "7,0.6000"
    ]

    assert lines == expected_lines, f"Content of {TEST_FINAL_PATH} is incorrect. Expected {expected_lines}, got {lines}."


def test_script_processes_changed_inputs(canonical_run):
    write_file(TRAIN_PATH, "id,reading\n20,6\n10,2\n15,\n")
    write_file(TEST_PATH, "id,reading\n30,10\n25,\n")
    write_file(META_PATH, "id,factor\n30,2\n15,1\n25,3\n10,2\n20,2\n")

    expected_train = derive_expected(TRAIN_PATH, META_PATH, TRAIN_PATH)
    expected_test = derive_expected(TEST_PATH, META_PATH, TRAIN_PATH)

    remove_outputs()
    run_script()

    assert os.path.isfile(TRAIN_FINAL_PATH), f"Output file {TRAIN_FINAL_PATH} was not created."
    assert os.path.isfile(TEST_FINAL_PATH), f"Output file {TEST_FINAL_PATH} was not created."
    assert read_nonempty_lines(TRAIN_FINAL_PATH) == expected_train
    assert read_nonempty_lines(TEST_FINAL_PATH) == expected_test
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
