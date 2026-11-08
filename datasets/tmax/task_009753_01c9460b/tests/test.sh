#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import pytest

REPORT_FILE = "/home/user/consistency_report.json"
RELATIONAL_FILE = "/home/user/backup_metadata/relational_stats.txt"
DOCUMENT_FILE = "/home/user/backup_metadata/document_stats.json"
SCHEMA_FILE = "/home/user/backup_metadata/graph_schema.csv"

def test_report_file_exists():
    assert os.path.isfile(REPORT_FILE), f"The report file {REPORT_FILE} does not exist."

def test_report_content_correct():
    # Parse relational stats
    rel_counts = {}
    with open(RELATIONAL_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            # Format: table: <table_name> | rows: <count>
            parts = line.split("|")
            if len(parts) == 2:
                table_part = parts[0].strip()
                rows_part = parts[1].strip()
                if table_part.startswith("table:") and rows_part.startswith("rows:"):
                    table_name = table_part.split(":", 1)[1].strip()
                    count = int(rows_part.split(":", 1)[1].strip())
                    rel_counts[table_name] = count

    # Parse document stats
    doc_counts = {}
    with open(DOCUMENT_FILE, "r") as f:
        doc_data = json.load(f)
        for coll in doc_data.get("collections", []):
            doc_counts[coll["name"]] = coll["document_count"]

    # Parse schema and build expected report
    expected_report = {}
    with open(SCHEMA_FILE, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rel_table = row["rel_table"].strip()
            doc_coll = row["doc_collection"].strip()
            key = f"{rel_table}_{doc_coll}"

            rel_count = rel_counts.get(rel_table)
            doc_count = doc_counts.get(doc_coll)

            is_consistent = (rel_count == doc_count) and (rel_count is not None)
            expected_report[key] = is_consistent

    # Load actual report
    with open(REPORT_FILE, "r") as f:
        try:
            actual_report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_FILE} is not valid JSON.")

    # Compare
    assert isinstance(actual_report, dict), f"The report in {REPORT_FILE} must be a JSON object (dictionary)."

    for key, expected_val in expected_report.items():
        assert key in actual_report, f"Missing key '{key}' in {REPORT_FILE}."
        assert actual_report[key] is expected_val, f"Expected '{key}' to be {str(expected_val).lower()}, but got {str(actual_report[key]).lower()}."

    # Check for extra keys
    for key in actual_report.keys():
        assert key in expected_report, f"Unexpected key '{key}' found in {REPORT_FILE}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
