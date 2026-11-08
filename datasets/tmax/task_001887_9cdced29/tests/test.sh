#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import zipfile
import json
import pytest

def test_export_zip_exists():
    zip_path = "/home/user/research_data/export.zip"
    assert os.path.exists(zip_path), f"{zip_path} does not exist."
    assert os.path.isfile(zip_path), f"{zip_path} is not a file."

def test_normalized_logs_jsonl_exists():
    jsonl_path = "/home/user/research_data/normalized_logs.jsonl"
    assert os.path.exists(jsonl_path), f"{jsonl_path} does not exist."
    assert os.path.isfile(jsonl_path), f"{jsonl_path} is not a file."

def test_zip_contents():
    zip_path = "/home/user/research_data/export.zip"
    assert os.path.exists(zip_path), f"{zip_path} does not exist."

    with zipfile.ZipFile(zip_path, 'r') as z:
        namelist = z.namelist()
        assert "normalized_logs.jsonl" in namelist, "normalized_logs.jsonl not found in export.zip"
        assert len(namelist) == 1, f"export.zip should contain exactly one file, found {len(namelist)}: {namelist}"

def test_jsonl_content_and_structure():
    jsonl_path = "/home/user/research_data/normalized_logs.jsonl"
    assert os.path.exists(jsonl_path), f"{jsonl_path} does not exist."

    with open(jsonl_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 records in normalized_logs.jsonl, found {len(lines)}"

    records = []
    for i, line in enumerate(lines):
        try:
            record = json.loads(line)
            records.append(record)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse line {i+1} as JSON: {e}")

    expected_keys = {"station", "timestamp", "status", "notes"}
    for i, record in enumerate(records):
        assert isinstance(record, dict), f"Record {i+1} is not a JSON object"
        assert set(record.keys()) == expected_keys, f"Record {i+1} keys {set(record.keys())} do not match expected keys {expected_keys}"
        assert record["status"] == "VALID", f"Record {i+1} has status '{record['status']}', expected 'VALID'"

    expected_notes = {
        "正常に動作しています",
        "Система работает нормально",
        "Alles in Ordnung"
    }

    actual_notes = {r["notes"] for r in records}
    assert actual_notes == expected_notes, f"Parsed notes {actual_notes} do not match expected {expected_notes}"

    expected_records = {
        ("Tokyo_Station", "2021-10-01T10:00:00Z", "VALID", "正常に動作しています"),
        ("Moscow_Station", "2021-10-01T10:00:00Z", "VALID", "Система работает нормально"),
        ("Berlin_Station", "2021-10-01T11:00:00Z", "VALID", "Alles in Ordnung"),
    }
    actual_records = {
        (r["station"], r["timestamp"], r["status"], r["notes"])
        for r in records
    }
    assert actual_records == expected_records, f"Parsed records {actual_records} do not match expected records {expected_records}"

def test_zip_jsonl_content_matches_file():
    zip_path = "/home/user/research_data/export.zip"
    jsonl_path = "/home/user/research_data/normalized_logs.jsonl"

    if not os.path.exists(zip_path) or not os.path.exists(jsonl_path):
        pytest.skip("Required files not found")

    with open(jsonl_path, 'rb') as f:
        file_content = f.read()

    with zipfile.ZipFile(zip_path, 'r') as z:
        if "normalized_logs.jsonl" in z.namelist():
            with z.open("normalized_logs.jsonl") as f_zip:
                zip_content = f_zip.read()

            # Allow for minor differences in newline encoding between file and zip, but ideally they match
            assert zip_content.decode('utf-8').strip() == file_content.decode('utf-8').strip(), "Content of normalized_logs.jsonl in export.zip does not match the file on disk"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
