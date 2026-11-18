#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import pytest

CLEAN_DIR = "/home/user/clean_dataset"
MANIFEST_PATH = os.path.join(CLEAN_DIR, "manifest.json")

EXPECTED_FILES = {
    "data_1001.dat": "ID,Measurement,Notes\n1001,0.992,This is a successful run with some extra padding to ensure it exceeds the fifty byte minimum limit we established for valid files.\n",
    "dataset_3003.dat": "ID,Measurement,Notes\n3003,0.875,Successful run from the café. Padding added to ensure size exceeds fifty bytes.\n"
}

def test_clean_dir_exists():
    """Ensure the clean dataset directory was created."""
    assert os.path.isdir(CLEAN_DIR), f"Directory {CLEAN_DIR} is missing."

def test_manifest_exists_and_valid():
    """Ensure the manifest.json exists and contains the correct structure."""
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} is missing."

    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Manifest file {MANIFEST_PATH} is not valid JSON.")

    assert isinstance(manifest, dict), "Manifest should be a JSON object (dictionary)."
    assert set(manifest.keys()) == set(EXPECTED_FILES.keys()), \
        f"Manifest keys do not match expected files. Expected {list(EXPECTED_FILES.keys())}, found {list(manifest.keys())}."

def test_clean_files_exist_and_content():
    """Ensure the correct data files were copied, are UTF-8 encoded, and have correct content."""
    for filename, expected_content in EXPECTED_FILES.items():
        filepath = os.path.join(CLEAN_DIR, filename)
        assert os.path.isfile(filepath), f"Expected file {filepath} is missing."

        try:
            with open(filepath, "r", encoding="utf-8") as f:
                actual_content = f.read()
        except UnicodeDecodeError:
            pytest.fail(f"File {filepath} is not properly encoded in UTF-8.")

        assert actual_content == expected_content, f"Content of {filepath} does not match expected output."

def test_manifest_hashes_match():
    """Ensure the hashes in the manifest match the actual SHA-256 hashes of the files."""
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    for filename, expected_content in EXPECTED_FILES.items():
        expected_hash = hashlib.sha256(expected_content.encode("utf-8")).hexdigest()
        actual_hash = manifest.get(filename)

        assert actual_hash == expected_hash, \
            f"Hash for {filename} in manifest ({actual_hash}) does not match expected SHA-256 hash ({expected_hash})."

def test_no_extra_files():
    """Ensure no other files were incorrectly copied to the clean directory."""
    actual_files = [f for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    expected_all = list(EXPECTED_FILES.keys()) + ["manifest.json"]

    extra_files = set(actual_files) - set(expected_all)
    assert not extra_files, f"Unexpected files found in {CLEAN_DIR}: {extra_files}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
