#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import json
import os
import re
import zlib
import pytest

REPORT_PATH = "/home/user/incident_report.json"
ENCODER_PATH = "/home/user/encoder.py"
LOG_PATH = "/home/user/access.log"

ORIGINAL_RECORDS = [
    ("2023-10-15 08:23:12", "XhMBEgAAGkEABxIAR0IBAQcOEA0XExU="),
    ("2023-10-15 09:01:45", "RBEIHBcbQxMUEQAADwA="),
    ("2023-10-15 10:15:30", "AAMBBQ1KCRZGAwAKAEISAAANFAYDEhkfGw=="),
    ("2023-10-15 11:42:05", "XhMBEgAAGkEIDBYAAkIdBxMSRkIEAAARDA=="),
]
EXPECTED_CWES = ["CWE-79", "CWE-89", "CWE-89", "CWE-79"]


def extract_key_from_encoder():
    with open(ENCODER_PATH, "r", encoding="utf-8") as f:
        outer_source = f.read()

    outer_tree = ast.parse(outer_source)
    compressed_blob = None
    for node in ast.walk(outer_tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if node.func.attr == "b64decode" and node.args:
                value = ast.literal_eval(node.args[0])
                if isinstance(value, (bytes, str)):
                    compressed_blob = base64.b64decode(value)
                    break

    assert compressed_blob is not None, "Could not recover the embedded encoder source."
    inner_source = zlib.decompress(compressed_blob).decode("utf-8")
    inner_tree = ast.parse(inner_source)

    for node in ast.walk(inner_tree):
        if isinstance(node, ast.Assign):
            if any(isinstance(target, ast.Name) and target.id == "key" for target in node.targets):
                key = ast.literal_eval(node.value)
                assert isinstance(key, bytes) and key, "The encoder key must be non-empty bytes."
                return key

    pytest.fail("Could not extract the key from the supplied encoder.")


def parse_log_records():
    records = []
    pattern = re.compile(r"^\[([^\]]+)\]\s+GET\s+\S*[?&]payload=([^&\s]+)\s+HTTP/")
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        for line in f:
            match = pattern.search(line.strip())
            if match:
                records.append((match.group(1), match.group(2)))
    return records


def derive_expected_data():
    records = parse_log_records()
    assert records == ORIGINAL_RECORDS, "The supplied access log was modified or does not contain the original records."

    key = extract_key_from_encoder()
    assert key == b"s3cr3t_k3y", "The supplied encoder was modified or contains an unexpected key."

    expected = []
    for (timestamp, encoded_payload), cwe in zip(records, EXPECTED_CWES):
        ciphertext = base64.b64decode(encoded_payload, validate=True)
        plaintext = bytes(byte ^ key[i % len(key)] for i, byte in enumerate(ciphertext)).decode("utf-8")
        expected.append({
            "timestamp": timestamp,
            "decrypted_payload": plaintext,
            "cwe": cwe,
        })
    return expected


def test_incident_report_exists():
    assert os.path.isfile(REPORT_PATH), f"The incident report {REPORT_PATH} is missing."


def test_incident_report_content():
    assert os.path.isfile(REPORT_PATH), f"The incident report {REPORT_PATH} is missing."

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

    expected_data = derive_expected_data()

    assert isinstance(report_data, list), "The JSON report must be a list of objects."
    assert len(report_data) == len(expected_data), f"Expected {len(expected_data)} items in the report, found {len(report_data)}."

    for i, (actual, expected) in enumerate(zip(report_data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        assert actual.get("timestamp") == expected["timestamp"], f"Mismatch in timestamp at index {i}."
        assert actual.get("decrypted_payload") == expected["decrypted_payload"], f"Mismatch in decrypted_payload at index {i}."
        assert actual.get("cwe") == expected["cwe"], f"Mismatch in cwe at index {i}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
