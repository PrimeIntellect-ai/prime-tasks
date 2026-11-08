#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest
import csv

def test_clean_data_exists_and_content():
    clean_data_path = "/home/user/clean_data.csv"

    assert os.path.isfile(clean_data_path), f"File {clean_data_path} does not exist. Did you run the Go script?"

    expected_rows = [
        ["id", "age", "age_group", "review_tokens"],
        ["123e4567-e89b-12d3-a456-426614174000", "25", "youth", "great|product|highly|recommend"],
        ["123e4567-e89b-12d3-a456-426614174003", "65", "senior", "works|well|very|sturdy"],
        ["123e4567-e89b-12d3-a456-426614174004", "45", "adult", "awful|terrible"],
        ["123e4567-e89b-12d3-a456-426614174006", "30", "adult", "lots|of|spaces"]
    ]

    actual_rows = []
    with open(clean_data_path, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            actual_rows.append(row)

    assert actual_rows == expected_rows, f"Content of {clean_data_path} does not match the expected final state."

def test_process_go_exists():
    script_path = "/home/user/process.go"
    assert os.path.isfile(script_path), f"Go script {script_path} does not exist."
TEST_EOF

verify() {
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1

    RAW_BACKUP=$(mktemp)
    CLEAN_BACKUP=$(mktemp)
    cp /home/user/raw_data.csv "$RAW_BACKUP" || return 1
    cp /home/user/clean_data.csv "$CLEAN_BACKUP" || return 1
    trap 'cp "$RAW_BACKUP" /home/user/raw_data.csv; cp "$CLEAN_BACKUP" /home/user/clean_data.csv; rm -f "$RAW_BACKUP" "$CLEAN_BACKUP" /tmp/process-submission /tmp/dynamic_expected.csv' EXIT

    go build -o /tmp/process-submission /home/user/process.go || return 1

    # The submitted program must itself reproduce the required result for the
    # original input, rather than relying on a pre-created clean_data.csv.
    rm -f /home/user/clean_data.csv
    (cd /home/user && timeout 20s /tmp/process-submission) || return 1
    python3 - << 'PY' || return 1
import csv
import os

expected = [
    ["id", "age", "age_group", "review_tokens"],
    ["123e4567-e89b-12d3-a456-426614174000", "25", "youth", "great|product|highly|recommend"],
    ["123e4567-e89b-12d3-a456-426614174003", "65", "senior", "works|well|very|sturdy"],
    ["123e4567-e89b-12d3-a456-426614174004", "45", "adult", "awful|terrible"],
    ["123e4567-e89b-12d3-a456-426614174006", "30", "adult", "lots|of|spaces"],
]
path = "/home/user/clean_data.csv"
assert os.path.isfile(path), "program did not create clean_data.csv"
with open(path, newline="", encoding="utf-8") as f:
    actual = list(csv.reader(f))
assert actual == expected, "program did not reproduce the required original output"
PY

    # Generate a fresh, unpredictable valid CSV and independently derive its
    # expected output so a program that merely hardcodes the original CSV fails.
    python3 - << 'PY' || return 1
import csv
import uuid

nonce = uuid.uuid4().hex[:10]
valid = [
    (str(uuid.uuid4()), 18, f"  Bright{nonce}, PRODUCT.   Works,\tWell. "),
    (str(uuid.uuid4()), 29, "One,Two. THREE"),
    (str(uuid.uuid4()), 30, "Adult. boundary, test"),
    (str(uuid.uuid4()), 59, "Still ADULT."),
    (str(uuid.uuid4()), 60, "Senior, starts. here"),
    (str(uuid.uuid4()), 100, "  Oldest   valid.  "),
]
invalid = [
    ("not-a-uuid", "42", "bad id"),
    ("123e4567-e89b-12d3-a456-42661417400g", "42", "nonhex id"),
    (str(uuid.uuid4()), "17", "too young"),
    (str(uuid.uuid4()), "101", "too old"),
    (str(uuid.uuid4()), "notanage", "bad age"),
]

def group(age):
    if age <= 29:
        return "youth"
    if age <= 59:
        return "adult"
    return "senior"

def tokenize(text):
    return "|".join(text.lower().replace(",", "").replace(".", "").split())

with open("/home/user/raw_data.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["id", "age", "review"])
    for ident, age, review in valid:
        writer.writerow([ident, age, review])
    writer.writerows(invalid)

with open("/tmp/dynamic_expected.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["id", "age", "age_group", "review_tokens"])
    for ident, age, review in valid:
        writer.writerow([ident, str(age), group(age), tokenize(review)])
PY

    rm -f /home/user/clean_data.csv
    (cd /home/user && timeout 20s /tmp/process-submission) || return 1
    python3 - << 'PY' || return 1
import csv
import os

path = "/home/user/clean_data.csv"
assert os.path.isfile(path), "program did not create clean_data.csv for changed input"
with open("/tmp/dynamic_expected.csv", newline="", encoding="utf-8") as f:
    expected = list(csv.reader(f))
with open(path, newline="", encoding="utf-8") as f:
    actual = list(csv.reader(f))
assert actual == expected, "program output is incorrect for dynamically generated input"
PY
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
