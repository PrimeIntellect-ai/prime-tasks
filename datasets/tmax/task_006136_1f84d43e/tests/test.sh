#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import hashlib
from datetime import datetime, timedelta
import pytest

CLEANED_DATA_PATH = '/home/user/cleaned_data.csv'
SUMMARY_PATH = '/home/user/summary.json'

def test_cleaned_data_exists():
    assert os.path.isfile(CLEANED_DATA_PATH), f"File not found: {CLEANED_DATA_PATH}"

def test_summary_exists():
    assert os.path.isfile(SUMMARY_PATH), f"File not found: {SUMMARY_PATH}"

def test_summary_content():
    with open(SUMMARY_PATH, 'r') as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("summary.json is not a valid JSON file.")

    alice_hash = hashlib.sha256(b"Alice Smith").hexdigest()[:8]
    bob_hash = hashlib.sha256(b"Bob Jones").hexdigest()[:8]

    assert alice_hash in summary, f"Missing key {alice_hash} in summary.json"
    assert bob_hash in summary, f"Missing key {bob_hash} in summary.json"

    # Alice mean: 457.0 / 6 = 76.166... -> 76.17
    # Bob mean: 414.0 / 5 = 82.80
    assert abs(summary[alice_hash] - 76.17) < 0.001, f"Expected Alice's mean HR to be 76.17, got {summary[alice_hash]}"
    assert abs(summary[bob_hash] - 82.8) < 0.001, f"Expected Bob's mean HR to be 82.8, got {summary[bob_hash]}"

def test_cleaned_data_content():
    with open(CLEANED_DATA_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("cleaned_data.csv is empty.")

        expected_header = ["timestamp", "patient_id", "patient_name", "heart_rate", "notes"]
        # Allow for minor whitespace variations in header
        assert [h.strip() for h in header] == expected_header, f"Header mismatch. Expected {expected_header}, got {header}"

        rows = list(reader)

    assert len(rows) == 11, f"Expected exactly 11 data rows, got {len(rows)}."
    for row in rows:
        assert len(row) == 5, f"Expected exactly 5 columns in row, got {len(row)}: {row}"

    alice_hash = hashlib.sha256(b"Alice Smith").hexdigest()[:8]
    bob_hash = hashlib.sha256(b"Bob Jones").hexdigest()[:8]

    alice_rows = [r for r in rows if r[2] == alice_hash]
    bob_rows = [r for r in rows if r[2] == bob_hash]

    assert len(alice_rows) == 6, f"Expected 6 rows for Alice, got {len(alice_rows)}"
    assert len(bob_rows) == 5, f"Expected 5 rows for Bob, got {len(bob_rows)}"

    for row in rows:
        assert row[1] == "***-**-****", f"Patient ID not properly masked in row: {row}"

    # Check Alice's resampling and ffill
    alice_times = [r[0] for r in alice_rows]
    alice_hrs = [float(r[3]) for r in alice_rows]

    expected_alice_times = [
        "2023-10-01T10:00:00",
        "2023-10-01T10:01:00",
        "2023-10-01T10:02:00",
        "2023-10-01T10:03:00",
        "2023-10-01T10:04:00",
        "2023-10-01T10:05:00"
    ]
    expected_alice_hrs = [75.0, 75.0, 75.0, 78.0, 78.0, 76.0]

    assert alice_times == expected_alice_times, "Alice's timestamps were not resampled correctly."
    assert alice_hrs == expected_alice_hrs, "Alice's heart rates were not forward-filled correctly."

    # Check Bob's resampling and ffill
    bob_times = [r[0] for r in bob_rows]
    bob_hrs = [float(r[3]) for r in bob_rows]

    expected_bob_times = [
        "2023-10-01T10:00:00",
        "2023-10-01T10:01:00",
        "2023-10-01T10:02:00",
        "2023-10-01T10:03:00",
        "2023-10-01T10:04:00"
    ]
    expected_bob_hrs = [82.0, 82.0, 85.0, 85.0, 80.0]

    assert bob_times == expected_bob_times, "Bob's timestamps were not resampled correctly."
    assert bob_hrs == expected_bob_hrs, "Bob's heart rates were not forward-filled correctly."

    # Accept embedded newlines either preserved or standardized to spaces, then
    # verify that notes were forward-filled at every generated timestamp.
    def standardized(note):
        return note.replace('\r\n', '\n').replace('\r', '\n').replace('\n', ' ')

    alice_notes = [standardized(r[4]) for r in alice_rows]
    bob_notes = [standardized(r[4]) for r in bob_rows]

    expected_alice_notes = [
        "Patient resting comfortably.",
        "Patient resting comfortably.",
        "Patient resting comfortably.",
        "Slight elevation in heart rate.",
        "Slight elevation in heart rate.",
        "Stabilized."
    ]
    expected_bob_notes = [
        "Complained of dizziness and fatigue.",
        "Complained of dizziness and fatigue.",
        "Administered water.",
        "Administered water.",
        "Patient asleep."
    ]

    assert alice_notes == expected_alice_notes, "Alice's notes were not parsed and forward-filled correctly."
    assert bob_notes == expected_bob_notes, "Bob's notes were not parsed and forward-filled correctly."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
