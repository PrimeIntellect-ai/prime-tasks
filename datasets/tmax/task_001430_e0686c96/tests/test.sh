#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import hashlib
from datetime import datetime
import pytest

PROCESSED_DIR = "/home/user/processed"
CLEAN_DATA_CSV = os.path.join(PROCESSED_DIR, "clean_data.csv")
SUMMARY_JSON = os.path.join(PROCESSED_DIR, "summary.json")
INPUT_DIR = "/home/user/input_data"
INPUT_FILES = [
    ("survey_na.csv", "utf-8"),
    ("survey_eu.csv", "iso-8859-1"),
    ("survey_ap.csv", "shift_jis"),
]
EXPECTED_COLUMNS = ["user_id", "timestamp", "question", "feedback_hash", "feedback"]


def parse_timestamp(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def derive_expected_outputs():
    winners = {}

    for filename, encoding in INPUT_FILES:
        path = os.path.join(INPUT_DIR, filename)
        with open(path, "r", encoding=encoding, newline="") as f:
            reader = csv.DictReader(f)
            assert reader.fieldnames == [
                "user_id", "timestamp", "q1_feedback", "q2_feedback", "q3_feedback"
            ]

            for source_row in reader:
                for question in ("q1", "q2", "q3"):
                    feedback = source_row[f"{question}_feedback"].strip()
                    if not feedback:
                        continue

                    feedback_hash = hashlib.sha256(feedback.encode("utf-8")).hexdigest()
                    candidate = {
                        "user_id": source_row["user_id"],
                        "timestamp": source_row["timestamp"],
                        "question": question,
                        "feedback_hash": feedback_hash,
                        "feedback": feedback,
                    }
                    rank = (parse_timestamp(candidate["timestamp"]), candidate["user_id"])
                    if feedback_hash not in winners or rank < winners[feedback_hash][0]:
                        winners[feedback_hash] = (rank, candidate)

    rows = [entry[1] for entry in winners.values()]
    rows.sort(key=lambda r: (r["question"], parse_timestamp(r["timestamp"]), r["user_id"]))

    summary = {"q1": 0, "q2": 0, "q3": 0}
    for row in rows:
        summary[row["question"]] += 1
    return rows, summary


EXPECTED_ROWS, EXPECTED_SUMMARY = derive_expected_outputs()


def test_processed_files_exist():
    """Ensure the processed directory and output files are created."""
    assert os.path.isdir(PROCESSED_DIR), f"Directory {PROCESSED_DIR} does not exist."
    assert os.path.exists(CLEAN_DATA_CSV), f"File {CLEAN_DATA_CSV} does not exist."
    assert os.path.exists(SUMMARY_JSON), f"File {SUMMARY_JSON} does not exist."


def test_summary_json_contents():
    """Verify that summary counts are derived from the supplied survey inputs."""
    with open(SUMMARY_JSON, "r", encoding="utf-8") as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{SUMMARY_JSON} is not valid JSON.")

    assert summary == EXPECTED_SUMMARY, \
        f"Expected summary {EXPECTED_SUMMARY}, but got {summary}."


def test_clean_data_csv_structure_and_contents():
    """Verify structure, provenance, hashing, deduplication, and sorting."""
    with open(CLEAN_DATA_CSV, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)

        assert reader.fieldnames == EXPECTED_COLUMNS, \
            f"Expected columns {EXPECTED_COLUMNS}, but got {reader.fieldnames}."
        rows = list(reader)

    assert len(rows) == len(EXPECTED_ROWS), \
        f"Expected exactly {len(EXPECTED_ROWS)} rows after deduplication, got {len(rows)}."

    seen_hashes = set()
    for row in rows:
        feedback = row["feedback"]
        assert feedback.strip() != "", \
            f"Row with user_id {row['user_id']} has empty or whitespace-only feedback."

        expected_hash = hashlib.sha256(feedback.strip().encode("utf-8")).hexdigest()
        assert row["feedback_hash"] == expected_hash, \
            f"Hash mismatch for user_id {row['user_id']}. Expected {expected_hash}, got {row['feedback_hash']}."

        assert expected_hash not in seen_hashes, \
            f"Duplicate feedback hash found: {expected_hash} for feedback '{feedback}'."
        seen_hashes.add(expected_hash)

    def sort_key(row):
        return (row["question"], row["timestamp"], row["user_id"])

    sorted_rows = sorted(rows, key=sort_key)
    for i, (actual, expected) in enumerate(zip(rows, sorted_rows)):
        assert actual == expected, \
            f"Row at index {i} is out of order. Expected {expected}, got {actual}. Data must be sorted by question, timestamp, then user_id."

    assert rows == EXPECTED_ROWS, \
        "clean_data.csv does not contain the rows derived from the supplied inputs using the required global deduplication rules."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
