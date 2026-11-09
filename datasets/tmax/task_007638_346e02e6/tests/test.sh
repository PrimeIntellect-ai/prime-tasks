#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import unicodedata
import pytest

def get_expected_state(input_csv):
    total = 0
    clean_rows = []
    anomaly_count = 0
    duplicate_count = 0
    seen = set()

    with open(input_csv, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        for row in reader:
            total += 1
            text = row['Text']
            norm_text = unicodedata.normalize('NFC', text)
            row['Text'] = norm_text

            user_id = row['UserID']
            dup_key = (user_id, norm_text)

            if dup_key in seen:
                duplicate_count += 1
                continue

            seen.add(dup_key)

            is_anomaly = False
            if len(norm_text) > 0:
                count = 1
                prev_char = norm_text[0]
                for char in norm_text[1:]:
                    if char == prev_char:
                        count += 1
                        if count >= 10:
                            is_anomaly = True
                            break
                    else:
                        count = 1
                        prev_char = char

            if is_anomaly:
                anomaly_count += 1
            else:
                clean_rows.append(row)

    return total, clean_rows, anomaly_count, duplicate_count, fieldnames

@pytest.fixture(scope="module")
def expected_data():
    input_csv = "/home/user/reviews.csv"
    assert os.path.exists(input_csv), f"Input file {input_csv} is missing."
    return get_expected_state(input_csv)

def test_cleaned_reviews_csv(expected_data):
    total, expected_clean_rows, anomaly_count, duplicate_count, expected_fieldnames = expected_data
    output_csv = "/home/user/cleaned_reviews.csv"

    assert os.path.exists(output_csv), f"Output file {output_csv} was not generated."

    with open(output_csv, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        actual_fieldnames = reader.fieldnames
        actual_rows = list(reader)

    assert actual_fieldnames == expected_fieldnames, f"Cleaned CSV headers {actual_fieldnames} do not match expected {expected_fieldnames}."

    assert len(actual_rows) == len(expected_clean_rows), f"Expected {len(expected_clean_rows)} clean rows, but found {len(actual_rows)} in {output_csv}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_clean_rows)):
        assert actual == expected, f"Row {i+1} in {output_csv} does not match expected. Actual: {actual}, Expected: {expected}"

def test_report_md(expected_data):
    total, expected_clean_rows, anomaly_count, duplicate_count, _ = expected_data
    report_file = "/home/user/report.md"

    assert os.path.exists(report_file), f"Report file {report_file} was not generated."

    with open(report_file, 'r', encoding='utf-8') as f:
        content = f.read()

    expected_content = f"""# Review Processing Report
Total Reviews Parsed: {total}
Clean Reviews: {len(expected_clean_rows)}
Anomalous Reviews: {anomaly_count}
Duplicates Removed: {duplicate_count}
"""
    assert content.strip() == expected_content.strip(), f"Content of {report_file} does not match the expected output. Actual:\n{content}\nExpected:\n{expected_content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
