#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import stat
import subprocess

import pytest
from scipy import stats

HOME = "/home/user"

EXPECTED_DATA = [
    {"id": "1", "text": "hello world"},
    {"id": "2", "text": "testing embeddings here"},
    {"id": "", "text": "missing id row"},
    {"id": "3", "text": "another text"},
    {"id": "4", "text": "foo bar baz"},
    {"id": "5", "text": "short"},
    {"id": "", "text": "another missing"},
    {"id": "6", "text": "a bit longer text for group B"},
]
EXPECTED_METADATA = [
    {"id": "1", "group": "A"},
    {"id": "2", "group": "A"},
    {"id": "3", "group": "B"},
    {"id": "4", "group": "B"},
    {"id": "5", "group": "A"},
    {"id": "6", "group": "B"},
]
EXPECTED_PROCESSED = [
    [row["id"], str(len(row["text"]))]
    for row in EXPECTED_DATA if row["id"]
]
EXPECTED_JOINED = [
    ["1", "11", "A"],
    ["2", "23", "A"],
    ["3", "12", "B"],
    ["4", "11", "B"],
    ["5", "5", "A"],
    ["6", "29", "B"],
]
EXPECTED_P = float(stats.ttest_ind([11, 23, 5], [12, 11, 29]).pvalue)


def read_dicts(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def read_rows(path):
    with open(path, newline="") as f:
        return list(csv.reader(f))


@pytest.fixture(scope="session", autouse=True)
def execute_and_validate_artifacts():
    preprocess = os.path.join(HOME, "preprocess.py")
    pipeline = os.path.join(HOME, "pipeline.sh")
    data_path = os.path.join(HOME, "data.csv")
    metadata_path = os.path.join(HOME, "metadata.csv")

    for path in (preprocess, pipeline, data_path, metadata_path):
        assert os.path.isfile(path), f"Missing required file: {path}"
        assert stat.S_ISREG(os.stat(path).st_mode), f"Not a regular file: {path}"

    assert read_dicts(data_path) == EXPECTED_DATA, "data.csv was modified"
    assert read_dicts(metadata_path) == EXPECTED_METADATA, "metadata.csv was modified"

    # Exercise preprocess.py independently on controlled input so pre-created output
    # files cannot satisfy the verifier and missing IDs must actually be handled.
    with open(data_path, "rb") as f:
        original_data = f.read()
    try:
        with open(data_path, "w", newline="") as f:
            f.write("id,text\n10,abc\n,drop me\n2,hello!\n")
        processed = os.path.join(HOME, "processed_data.csv")
        if os.path.lexists(processed):
            os.remove(processed)
        subprocess.run(
            ["python3", preprocess], cwd=HOME, check=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        rows = read_rows(processed)
        assert rows == [["id", "embedding"], ["10", "3"], ["2", "6"]], (
            "preprocess.py did not drop the missing-ID row, cast IDs to integers, "
            "and compute the expected embeddings"
        )
    finally:
        with open(data_path, "wb") as f:
            f.write(original_data)

    # Remove prior products and really run the requested pipeline.
    for name in ("processed_data.csv", "sorted_processed.csv", "sorted_metadata.csv",
                 "joined.csv", "results.txt"):
        path = os.path.join(HOME, name)
        if os.path.lexists(path):
            os.remove(path)
    subprocess.run(
        ["bash", pipeline], cwd=HOME, check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )


def test_processed_data_csv_fixed():
    path = "/home/user/processed_data.csv"
    assert os.path.isfile(path), f"Missing file: {path}. Did you run the pipeline?"
    with open(path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) > 1, f"File {path} is empty or missing data."

    # Check that IDs are integers and no empty IDs exist.
    for line in lines[1:]:
        parts = line.split(',')
        assert len(parts) >= 2, f"Invalid format in {path}: {line}"
        id_val = parts[0].strip()
        assert id_val != "", f"Found missing ID in {path}. Rows with missing IDs should be dropped."
        assert '.' not in id_val, f"ID is not an integer in {path}: '{id_val}'. It must be cast to int."

    assert read_rows(path) == [["id", "embedding"]] + EXPECTED_PROCESSED, (
        "processed_data.csv does not contain the records and text lengths derived from data.csv"
    )


def test_joined_csv_not_empty():
    path = "/home/user/joined.csv"
    assert os.path.isfile(path), f"Missing file: {path}. Did you run the pipeline?"
    with open(path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == 6, f"Expected 6 joined rows in {path}, got {len(lines)}. The join command failed to match correctly."
    assert read_rows(path) == EXPECTED_JOINED, "joined.csv does not contain the expected joined records"


def test_results_txt_valid():
    path = "/home/user/results.txt"
    assert os.path.isfile(path), f"Missing file: {path}. Did you run the pipeline?"
    with open(path, "r") as f:
        content = f.read()

    assert "p-value: NaN" not in content, "results.txt contains 'p-value: NaN'. The T-test failed due to empty or invalid data."
    assert "p-value:" in content, "results.txt does not contain the expected 'p-value:' output."
    match = re.fullmatch(r"\s*p-value:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)\s*", content)
    assert match, "results.txt does not contain exactly one numeric p-value result"
    assert math.isclose(float(match.group(1)), EXPECTED_P, rel_tol=1e-12, abs_tol=1e-12), (
        f"results.txt has the wrong p-value; expected {EXPECTED_P}"
    )


def test_final_p_value_txt_correct():
    path = "/home/user/final_p_value.txt"
    assert os.path.isfile(path), f"Missing file: {path}. You must create this file with the extracted p-value."
    with open(path, "r") as f:
        content = f.read().strip()

    try:
        p_val = float(content)
    except ValueError:
        pytest.fail(f"final_p_value.txt does not contain a valid numeric float: '{content}'")

    assert re.fullmatch(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", content), (
        "final_p_value.txt must contain only the numeric p-value"
    )
    assert math.isclose(p_val, EXPECTED_P, rel_tol=1e-3), (
        f"Extracted p-value {p_val} is incorrect. Expected approximately {EXPECTED_P}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
