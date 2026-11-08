#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import re
import csv

def process_line(line):
    data = json.loads(line)

    id_val = data.get("id", "")
    user_val = data.get("user", "")
    review_val = data.get("review", "")

    # Extract email domain
    email_domain = ""
    email_match = re.search(r'<[a-zA-Z0-9._%+-]+@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})>', user_val)
    if email_match:
        email_domain = email_match.group(1)

    # Anonymize user
    anonymized_user = re.sub(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', '[EMAIL]', user_val)

    # Anonymize review
    anonymized_review = re.sub(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', '[EMAIL]', review_val)
    anonymized_review = re.sub(r'\b\d{3}-\d{4}\b', '[PHONE]', anonymized_review)

    # Word count
    # equivalent to awk '{print NF}' or wc -w
    word_count = len(anonymized_review.split())

    return [str(id_val), anonymized_user, anonymized_review, email_domain, str(word_count)]

def csv_field_quote_flags(line):
    """Return whether each field in one CSV record is double-quoted."""
    flags = []
    i = 0
    n = len(line)

    while True:
        quoted = i < n and line[i] == '"'
        flags.append(quoted)

        if quoted:
            i += 1
            closed = False
            while i < n:
                if line[i] == '"':
                    if i + 1 < n and line[i + 1] == '"':
                        i += 2
                    else:
                        i += 1
                        closed = True
                        break
                else:
                    i += 1
            assert closed, "Unterminated quoted CSV field."
            assert i == n or line[i] == ',', "Unexpected characters after a quoted CSV field."
        else:
            while i < n and line[i] != ',':
                i += 1

        if i == n:
            break
        i += 1

    return flags

def test_cleaned_reviews_exists():
    assert os.path.exists("/home/user/cleaned_reviews.csv"), "The output file /home/user/cleaned_reviews.csv does not exist."
    assert os.path.isfile("/home/user/cleaned_reviews.csv"), "/home/user/cleaned_reviews.csv is not a file."

def test_cleaned_reviews_content():
    raw_file = "/home/user/raw_reviews.jsonl"
    cleaned_file = "/home/user/cleaned_reviews.csv"

    assert os.path.exists(raw_file), f"Input file {raw_file} is missing."
    assert os.path.exists(cleaned_file), f"Output file {cleaned_file} is missing."

    with open(raw_file, "r", encoding="utf-8") as f:
        raw_lines = f.read().splitlines()

    expected_rows = [process_line(line) for line in raw_lines]

    with open(cleaned_file, "r", encoding="utf-8") as f:
        # The prompt requires double quotes for anonymized_user and anonymized_review.
        # Python's csv module handles this, but let's read it properly.
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in CSV, but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert len(actual) == 5, f"Row {i+1} does not have exactly 5 columns."
        assert actual[0] == expected[0], f"Row {i+1}: ID mismatch. Expected {expected[0]}, got {actual[0]}."
        assert actual[1] == expected[1], f"Row {i+1}: Anonymized user mismatch. Expected {expected[1]}, got {actual[1]}."
        assert actual[2] == expected[2], f"Row {i+1}: Anonymized review mismatch. Expected {expected[2]}, got {actual[2]}."
        assert actual[3] == expected[3], f"Row {i+1}: Email domain mismatch. Expected {expected[3]}, got {actual[3]}."
        assert actual[4] == expected[4], f"Row {i+1}: Word count mismatch. Expected {expected[4]}, got {actual[4]}."

def test_csv_formatting():
    # Ensure quotes are actually present in the raw file lines as required
    cleaned_file = "/home/user/cleaned_reviews.csv"
    assert os.path.exists(cleaned_file), f"Output file {cleaned_file} is missing."

    with open(cleaned_file, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    for i, line in enumerate(lines):
        parts = line.split(',')
        if len(parts) >= 3:
            assert '"' in line, f"Row {i+1} does not seem to contain double quotes as required."

        quote_flags = csv_field_quote_flags(line)
        assert len(quote_flags) == 5, f"Row {i+1} does not have exactly 5 CSV fields."
        assert quote_flags[1], f"Row {i+1}: anonymized_user field is not enclosed in double quotes."
        assert quote_flags[2], f"Row {i+1}: anonymized_review field is not enclosed in double quotes."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
