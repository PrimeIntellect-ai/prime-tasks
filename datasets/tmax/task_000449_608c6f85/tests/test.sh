#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

CLEAN_CSV_PATH = '/home/user/data/clean_transactions.csv'
SUMMARY_TXT_PATH = '/home/user/data/summary.txt'

def test_clean_transactions_exists():
    """Test that the clean_transactions.csv file was created."""
    assert os.path.isfile(CLEAN_CSV_PATH), f"{CLEAN_CSV_PATH} is missing."

def test_summary_exists():
    """Test that the summary.txt file was created."""
    assert os.path.isfile(SUMMARY_TXT_PATH), f"{SUMMARY_TXT_PATH} is missing."

def test_clean_transactions_content_and_encoding():
    """Test that clean_transactions.csv is UTF-8 encoded, deduplicated, and emails are masked."""
    try:
        with open(CLEAN_CSV_PATH, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            rows = list(reader)
    except UnicodeDecodeError:
        pytest.fail(f"{CLEAN_CSV_PATH} is not properly encoded in UTF-8.")

    assert len(rows) > 0, f"{CLEAN_CSV_PATH} is empty."

    headers = rows[0]
    expected_headers = ['transaction_id', 'customer_name', 'email', 'amount', 'notes']
    assert headers == expected_headers, f"Headers in {CLEAN_CSV_PATH} do not match expected: {expected_headers}"

    data_rows = rows[1:]
    assert len(data_rows) == 5, f"Expected 5 data rows after deduplication, but found {len(data_rows)}."

    expected_data = [
        ['T001', 'José Silva', 'j***@example.com', '150.00', 'Pago de café'],
        ['T002', 'Maria García', 'm***@test.org', '200.50', 'Reembolso'],
        ['T003', 'René Descartes', 'r***@philosophy.fr', '99.99', "L'achat"],
        ['T004', 'Jürgen Müller', 'j***@berlin.de', '50.00', 'Groß'],
        ['T005', 'François Dubois', 'f***@paris.fr', '12.50', 'Très bien']
    ]

    for i, expected_row in enumerate(expected_data):
        assert data_rows[i] == expected_row, f"Row {i+1} in {CLEAN_CSV_PATH} does not match expected. Got {data_rows[i]}, expected {expected_row}."

def test_summary_content():
    """Test that summary.txt contains the correct ETL summary."""
    with open(SUMMARY_TXT_PATH, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    expected_content = (
        "ETL Run Summary\n"
        "Raw records: 7\n"
        "Unique records: 5\n"
        "Duplicates removed: 2"
    )

    assert content == expected_content, f"Content of {SUMMARY_TXT_PATH} does not match expected format and counts."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
