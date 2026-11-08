#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
from collections import Counter, defaultdict
from decimal import Decimal, InvalidOperation

SOURCE_PATH = "/home/user/data/purchases.csv"
CLEANED_PATH = "/home/user/output/cleaned.csv"
BOOTSTRAP_PATH = "/home/user/output/bootstrap.csv"
REC_PATH = "/home/user/output/recommendations.csv"
HEADER = ["user_id", "item_id", "rating"]


def expected_cleaned_rows():
    with open(SOURCE_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        assert next(reader) == HEADER
        source_rows = list(reader)

    valid_rows = []
    for row in source_rows:
        assert len(row) == 3, f"Malformed source row: {row}"
        try:
            rating = Decimal(row[2])
        except (InvalidOperation, ValueError):
            continue
        if Decimal("1.0") <= rating <= Decimal("5.0"):
            valid_rows.append(row)

    counts = Counter(row[0] for row in valid_rows)
    outlier_users = {user for user, count in counts.items() if count > 5}
    return [row for row in valid_rows if row[0] not in outlier_users]


def test_cleaned_csv_exists_and_correct():
    assert os.path.isfile(CLEANED_PATH), f"File not found: {CLEANED_PATH}"

    with open(CLEANED_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        lines = list(reader)

    assert len(lines) > 0, f"{CLEANED_PATH} is empty"
    header = lines[0]
    assert header == HEADER, f"Incorrect header in {CLEANED_PATH}"

    data_lines = lines[1:]
    assert all(len(row) == 3 for row in data_lines), "Every cleaned row must have exactly three columns"
    users = set(row[0] for row in data_lines if len(row) > 0)

    assert "U4" not in users, "User U4 should have been removed (outlier > 5 valid purchases)."
    assert "U5" not in users, "User U5 should have been removed (invalid ratings)."
    assert "U6" not in users, "User U6 should have been removed (invalid rating)."
    assert "U1" in users and "U2" in users and "U3" in users, "Valid users U1, U2, U3 should be in the cleaned dataset."
    assert len(data_lines) == 9, f"Expected 9 data rows in {CLEANED_PATH}, found {len(data_lines)}"

    expected = expected_cleaned_rows()
    assert Counter(map(tuple, data_lines)) == Counter(map(tuple, expected)), \
        "cleaned.csv does not contain exactly the valid, non-outlier source purchases"


def test_bootstrap_csv_exists_and_correct():
    assert os.path.isfile(BOOTSTRAP_PATH), f"File not found: {BOOTSTRAP_PATH}"

    with open(BOOTSTRAP_PATH, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == 501, f"Expected exactly 501 lines in {BOOTSTRAP_PATH} (1 header + 500 data), found {len(lines)}"
    assert lines[0] == "user_id,item_id,rating", f"Incorrect header in {BOOTSTRAP_PATH}"

    with open(CLEANED_PATH, "r") as f:
        cleaned_lines = set(f.read().splitlines()[1:])

    for i, line in enumerate(lines[1:], start=2):
        assert line in cleaned_lines, f"Row {i} in {BOOTSTRAP_PATH} ('{line}') is not a valid row from {CLEANED_PATH}"

    with open(BOOTSTRAP_PATH, "r", newline="") as f:
        parsed = list(csv.reader(f))
    assert parsed[0] == HEADER
    assert len(parsed[1:]) == 500
    assert all(len(row) == 3 for row in parsed[1:]), "Every bootstrap row must have exactly three columns"


def test_recommendations_csv_exists_and_correct():
    assert os.path.isfile(REC_PATH), f"File not found: {REC_PATH}"

    with open(REC_PATH, "r") as f:
        content = f.read().strip().splitlines()

    expected_content = [
        "recommended_item_id,co_occurrence_count",
        "ITEM_002,3",
        "ITEM_003,2",
        "ITEM_004,1"
    ]
    assert content == expected_content, f"Content of {REC_PATH} does not match expected recommendations."

    user_items = defaultdict(set)
    for user_id, item_id, rating in expected_cleaned_rows():
        user_items[user_id].add(item_id)

    target_users = {user for user, items in user_items.items() if "ITEM_001" in items}
    candidate_items = set().union(*(user_items[user] for user in target_users)) if target_users else set()
    candidate_items.discard("ITEM_001")
    counts = {
        item: sum(1 for user in target_users if item in user_items[user])
        for item in candidate_items
    }
    top_three = sorted(counts.items(), key=lambda pair: (-pair[1], pair[0]))[:3]
    derived_content = ["recommended_item_id,co_occurrence_count"] + [
        f"{item},{count}" for item, count in top_three
    ]
    assert content == derived_content, "Recommendations were not correctly derived from the cleaned source purchases"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
