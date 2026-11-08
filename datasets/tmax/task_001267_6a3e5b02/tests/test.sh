#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import hashlib
import pytest

ARTIFACTS_DIR = "/home/user/artifacts"
APP1_PATH = os.path.join(ARTIFACTS_DIR, "app1.bin")
APP2_PATH = os.path.join(ARTIFACTS_DIR, "app2.bin")
APP3_PATH = os.path.join(ARTIFACTS_DIR, "app3.bin")
MANIFEST_PATH = os.path.join(ARTIFACTS_DIR, "manifest.json")
SUMMARY_PATH = os.path.join(ARTIFACTS_DIR, "summary.csv")

EXPECTED_APP1_BYTES = b'\x11\x22\x33\xCA\xFE\xBA\xBE\x00\x00\x44\x55'
EXPECTED_APP2_BYTES = b'\xAA\xBB\xCC\xDD'
EXPECTED_APP3_BYTES = b'\xCA\xFE\xBA\xBE\x00\x00\x12\x34\xCA\xFE\xBA\xBE\x00\x00'

def compute_sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def test_binaries_patched_correctly():
    """Check that the binary files have the exact expected bytes after patching."""
    assert os.path.isfile(APP1_PATH), f"File {APP1_PATH} is missing."
    with open(APP1_PATH, "rb") as f:
        app1_content = f.read()
    assert app1_content == EXPECTED_APP1_BYTES, f"Content of {APP1_PATH} was not patched correctly."

    assert os.path.isfile(APP2_PATH), f"File {APP2_PATH} is missing."
    with open(APP2_PATH, "rb") as f:
        app2_content = f.read()
    assert app2_content == EXPECTED_APP2_BYTES, f"Content of {APP2_PATH} should not have been altered."

    assert os.path.isfile(APP3_PATH), f"File {APP3_PATH} is missing."
    with open(APP3_PATH, "rb") as f:
        app3_content = f.read()
    assert app3_content == EXPECTED_APP3_BYTES, f"Content of {APP3_PATH} was not patched correctly."

def test_manifest_updated():
    """Check that manifest.json contains the correct new SHA-256 hashes."""
    assert os.path.isfile(MANIFEST_PATH), f"File {MANIFEST_PATH} is missing."

    with open(MANIFEST_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{MANIFEST_PATH} is not valid JSON.")

    assert "artifacts" in data, f"'artifacts' key missing in {MANIFEST_PATH}"

    expected_hashes = {
        "app1.bin": compute_sha256(EXPECTED_APP1_BYTES),
        "app2.bin": compute_sha256(EXPECTED_APP2_BYTES),
        "app3.bin": compute_sha256(EXPECTED_APP3_BYTES),
    }

    actual_hashes = {item.get("name"): item.get("sha256") for item in data.get("artifacts", [])}

    for app_name, expected_hash in expected_hashes.items():
        assert app_name in actual_hashes, f"{app_name} is missing from the manifest."
        assert actual_hashes[app_name] == expected_hash, f"Incorrect hash for {app_name} in manifest.json."

def test_summary_csv_created_and_correct():
    """Check that summary.csv is created with correct headers, rows, and sorting."""
    assert os.path.isfile(SUMMARY_PATH), f"File {SUMMARY_PATH} is missing."

    expected_hashes = {
        "app1.bin": compute_sha256(EXPECTED_APP1_BYTES),
        "app2.bin": compute_sha256(EXPECTED_APP2_BYTES),
        "app3.bin": compute_sha256(EXPECTED_APP3_BYTES),
    }

    with open(SUMMARY_PATH, "r", newline="") as f:
        reader = list(csv.reader(f))

    assert len(reader) > 0, "summary.csv is empty."

    header = reader[0]
    assert header == ["artifact_name", "new_sha256"], f"Incorrect header in summary.csv: {header}"

    rows = reader[1:]
    assert len(rows) == 3, f"Expected 3 rows in summary.csv, got {len(rows)}."

    # Check sorting
    artifact_names = [row[0] for row in rows if len(row) > 0]
    assert artifact_names == sorted(artifact_names), "Rows in summary.csv are not sorted alphabetically by artifact_name."

    # Check values
    for row in rows:
        assert len(row) == 2, f"Malformed row in summary.csv: {row}"
        name, sha256_val = row
        assert name in expected_hashes, f"Unexpected artifact_name {name} in summary.csv."
        assert sha256_val == expected_hashes[name], f"Incorrect hash for {name} in summary.csv."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
