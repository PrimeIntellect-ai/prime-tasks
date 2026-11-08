#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import xml.etree.ElementTree as ET
import pytest

def time_to_seconds(t_str):
    if ":" in t_str:
        parts = t_str.split(":")
        h = float(parts[0])
        m = float(parts[1])
        s = float(parts[2])
        return h * 3600 + m * 60 + s
    else:
        return float(t_str)

def transform_time(t_sec):
    return round((t_sec * 1.05) + 1.25, 3)

def compute_math_score(text):
    math_chars = {'+', '-', '=', '^', '_', '\\'}
    return sum(1 for char in text if char in math_chars)

@pytest.fixture(scope="module")
def expected_data():
    data = []

    # Process en.json
    en_path = "/home/user/locales/en.json"
    if os.path.exists(en_path):
        with open(en_path, "r") as f:
            en_json = json.load(f)
            for item in en_json:
                data.append({
                    "lang": "en",
                    "id": int(item["id"]),
                    "start_adj": transform_time(time_to_seconds(item["start"])),
                    "end_adj": transform_time(time_to_seconds(item["end"])),
                    "math_score": compute_math_score(item["text"])
                })

    # Process es.xml
    es_path = "/home/user/locales/es.xml"
    if os.path.exists(es_path):
        tree = ET.parse(es_path)
        for sub in tree.getroot().findall("sub"):
            data.append({
                "lang": "es",
                "id": int(sub.attrib["id"]),
                "start_adj": transform_time(time_to_seconds(sub.attrib["start"])),
                "end_adj": transform_time(time_to_seconds(sub.attrib["end"])),
                "math_score": compute_math_score(sub.find("text").text or "")
            })

    # Process fr.csv
    fr_path = "/home/user/locales/fr.csv"
    if os.path.exists(fr_path):
        with open(fr_path, "r", newline='') as f:
            reader = csv.DictReader(f)
            for row in reader:
                data.append({
                    "lang": "fr",
                    "id": int(row["id"]),
                    "start_adj": transform_time(time_to_seconds(row["start"])),
                    "end_adj": transform_time(time_to_seconds(row["end"])),
                    "math_score": compute_math_score(row["text"])
                })

    # Sort by id ascending, then lang ascending
    data.sort(key=lambda x: (x["id"], x["lang"]))
    return data

def test_output_file_exists():
    assert os.path.isfile("/home/user/aligned_subs.jsonl"), "Output file /home/user/aligned_subs.jsonl does not exist."

def test_output_format_and_sorting(expected_data):
    output_path = "/home/user/aligned_subs.jsonl"
    assert os.path.isfile(output_path), "Missing output file."

    actual_data = []
    with open(output_path, "r") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                actual_data.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {output_path} is not a valid JSON object.")

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} records, found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert "lang" in actual, f"Row {i} is missing 'lang' key."
        assert "id" in actual, f"Row {i} is missing 'id' key."
        assert "start_adj" in actual, f"Row {i} is missing 'start_adj' key."
        assert "end_adj" in actual, f"Row {i} is missing 'end_adj' key."
        assert "math_score" in actual, f"Row {i} is missing 'math_score' key."

        assert actual["lang"] == expected["lang"], f"Row {i}: expected lang '{expected['lang']}', got '{actual['lang']}'. Is the file sorted correctly?"
        assert int(actual["id"]) == expected["id"], f"Row {i}: expected id {expected['id']}, got {actual['id']}. Is the file sorted correctly?"

        assert abs(float(actual["start_adj"]) - expected["start_adj"]) < 0.001, f"Row {i}: expected start_adj {expected['start_adj']}, got {actual['start_adj']}."
        assert abs(float(actual["end_adj"]) - expected["end_adj"]) < 0.001, f"Row {i}: expected end_adj {expected['end_adj']}, got {actual['end_adj']}."
        assert int(actual["math_score"]) == expected["math_score"], f"Row {i}: expected math_score {expected['math_score']}, got {actual['math_score']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
