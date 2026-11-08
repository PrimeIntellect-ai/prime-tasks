#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

OUTPUT_FILE = "/home/user/es_final.tsv"
INPUT_FILE = "/home/user/loc_exports.tsv"

def get_expected_data():
    if not os.path.exists(INPUT_FILE):
        pytest.fail(f"Input file {INPUT_FILE} is missing, cannot compute expected state.")

    es_records = {}
    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip("\n").split("\t")
            if len(parts) < 4:
                continue
            timestamp = int(parts[0])
            msg_id = int(parts[1])
            locale = parts[2]
            text = parts[3]

            if locale == "es-ES":
                if msg_id not in es_records or timestamp > es_records[msg_id][0]:
                    es_records[msg_id] = (timestamp, text)

    expected = {}
    for i in range(1, 51):
        if i in es_records:
            expected[i] = es_records[i][1]
        else:
            expected[i] = "¡TRADUCCIÓN PENDIENTE!"

    return expected

def test_final_file_exists():
    """Test that the final output file exists."""
    assert os.path.isfile(OUTPUT_FILE), f"The final file {OUTPUT_FILE} is missing."

def test_final_file_format_and_content():
    """Test that the final output file has exactly 50 lines, correct columns, and expected content."""
    expected_data = get_expected_data()

    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    assert len(lines) == 50, f"The file {OUTPUT_FILE} must contain exactly 50 lines. Found {len(lines)}."

    for i, line in enumerate(lines):
        expected_id = i + 1
        parts = line.split("\t")
        assert len(parts) == 2, f"Line {expected_id} does not contain exactly 2 columns (tab-separated)."

        try:
            actual_id = int(parts[0])
        except ValueError:
            pytest.fail(f"Line {expected_id} has an invalid MessageID: {parts[0]}")

        assert actual_id == expected_id, f"Expected MessageID {expected_id} on line {expected_id}, but found {actual_id}. Ensure the file is sorted."

        actual_text = parts[1]
        expected_text = expected_data[expected_id]

        assert actual_text == expected_text, f"For MessageID {expected_id}, expected text '{expected_text}', but got '{actual_text}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
