#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import pytest

CLEANED_FILE = "/home/user/cleaned.csv"
AUGMENTED_FILE = "/home/user/augmented.csv"
CLOSEST_SERVER_FILE = "/home/user/closest_server.txt"

def test_cleaned_csv_exists_and_correct():
    assert os.path.exists(CLEANED_FILE), f"{CLEANED_FILE} is missing."

    with open(CLEANED_FILE, "r") as f:
        reader = list(csv.reader(f))

    assert len(reader) > 0, f"{CLEANED_FILE} is empty."
    assert reader[0] == ["server_id", "cpu", "mem", "disk", "net", "state"], "Header is incorrect in cleaned.csv"

    expected_data = [
        ["SRV_001", "45", "60", "30", "80", "ACTIVE"],
        ["SRV_004", "51", "49", "50", "50", "ACTIVE"],
        ["SRV_005", "60", "40", "60", "20", "ACTIVE"],
        ["SRV_007", "49", "50", "50", "50", "ACTIVE"],
        ["SRV_008", "12", "90", "80", "90", "ACTIVE"]
    ]

    actual_data = reader[1:]
    assert actual_data == expected_data, "Data in cleaned.csv does not match the expected filtered rows."

def test_augmented_csv_exists_and_correct():
    assert os.path.exists(AUGMENTED_FILE), f"{AUGMENTED_FILE} is missing."

    with open(AUGMENTED_FILE, "r") as f:
        reader = list(csv.reader(f))

    assert len(reader) > 0, f"{AUGMENTED_FILE} is empty."
    assert reader[0] == ["server_id", "cpu", "mem", "disk", "net", "state"], "Header is incorrect in augmented.csv"

    expected_data = [
        ["SRV_001", "45", "60", "30", "80", "ACTIVE"],
        ["SRV_004", "51", "49", "50", "50", "ACTIVE"],
        ["SRV_005", "60", "40", "60", "20", "ACTIVE"],
        ["SRV_007", "49", "50", "50", "50", "ACTIVE"],
        ["SRV_007", "49", "50", "50", "50", "ACTIVE"],
        ["SRV_008", "12", "90", "80", "90", "ACTIVE"]
    ]

    actual_data = reader[1:]
    assert actual_data == expected_data, "Data in augmented.csv does not match the expected duplicated rows."

def test_closest_server_txt_exists_and_correct():
    assert os.path.exists(CLOSEST_SERVER_FILE), f"{CLOSEST_SERVER_FILE} is missing."

    with open(CLOSEST_SERVER_FILE, "r") as f:
        content = f.read().strip()

    assert content == "SRV_005", f"Expected closest server to be 'SRV_005', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
