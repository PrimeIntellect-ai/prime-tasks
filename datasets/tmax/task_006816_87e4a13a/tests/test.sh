#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import pytest

RAW_DIR = "/home/user/backups/raw"
PROCESSED_DIR = "/home/user/backups/processed"
MANIFEST_PATH = "/home/user/backups/manifest.json"

ORIGINAL_CONTENTS = {
    "export_A_final.txt": "SERVER,DATE,STATUS,METRIC\nWeb01,20231024,ACTIVE,4920\nWeb01,20231024,IDLE,112\n",
    "db_dump_random.txt": "SERVER,DATE,STATUS,METRIC\nDB_MAIN,20231025,SYNC,9999\nDB_MAIN,20231025,BACKUP,8888\n",
    "cache-log-11.txt": "SERVER,DATE,STATUS,METRIC\nREDIS_01,20231026,OK,555\nREDIS_01,20231026,WARN,444\n",
}

def derive_processed_name(content):
    lines = content.splitlines()
    fields = lines[1].split(',')
    return f"{fields[0].lower()}_{fields[1]}.csv"

EXPECTED_MAPPING = {
    original: derive_processed_name(content)
    for original, content in ORIGINAL_CONTENTS.items()
}
EXPECTED_ORIGINAL_FILES = set(EXPECTED_MAPPING)
EXPECTED_PROCESSED_FILES = set(EXPECTED_MAPPING.values())
EXPECTED_PROCESSED_CONTENTS = {
    EXPECTED_MAPPING[original]: content.lower()
    for original, content in ORIGINAL_CONTENTS.items()
}

def get_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(8192):
            h.update(chunk)
    return h.hexdigest()

def test_raw_directory_empty():
    assert os.path.exists(RAW_DIR), f"Directory {RAW_DIR} does not exist."
    files = os.listdir(RAW_DIR)
    assert len(files) == 0, f"Raw directory {RAW_DIR} is not empty. Contains: {files}"

def test_processed_files_exist_and_lowercase():
    assert os.path.exists(PROCESSED_DIR), f"Directory {PROCESSED_DIR} does not exist."

    actual_files = set(os.listdir(PROCESSED_DIR))
    for expected_file in EXPECTED_PROCESSED_FILES:
        assert expected_file in actual_files, f"Expected processed file '{expected_file}' not found in {PROCESSED_DIR}."

        filepath = os.path.join(PROCESSED_DIR, expected_file)
        assert os.path.isfile(filepath), f"Expected processed path '{expected_file}' is not a regular file."
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        assert content == content.lower(), f"File '{expected_file}' is not entirely lowercase."
        assert content == EXPECTED_PROCESSED_CONTENTS[expected_file], (
            f"File '{expected_file}' is not the lowercase transformation of its original raw file."
        )

def test_manifest_structure_and_checksums():
    assert os.path.exists(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} does not exist."

    with open(MANIFEST_PATH, 'r', encoding='utf-8') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Manifest file {MANIFEST_PATH} is not valid JSON.")

    assert "archives" in manifest, "Manifest JSON is missing the 'archives' key."
    archives = manifest["archives"]
    assert isinstance(archives, list), "'archives' must be a list."
    assert len(archives) == len(EXPECTED_ORIGINAL_FILES), f"Expected {len(EXPECTED_ORIGINAL_FILES)} entries in 'archives', found {len(archives)}."

    manifest_originals = set()
    manifest_processed = set()

    for entry in archives:
        assert "original" in entry, "An entry in 'archives' is missing the 'original' key."
        assert "processed" in entry, "An entry in 'archives' is missing the 'processed' key."
        assert "checksum" in entry, "An entry in 'archives' is missing the 'checksum' key."

        orig = entry["original"]
        proc = entry["processed"]
        chk = entry["checksum"]

        manifest_originals.add(orig)
        manifest_processed.add(proc)

        assert orig in EXPECTED_MAPPING, f"Unexpected original file '{orig}' in manifest."
        assert proc == EXPECTED_MAPPING[orig], (
            f"Manifest pairs original '{orig}' with '{proc}', expected '{EXPECTED_MAPPING[orig]}'."
        )

        proc_path = os.path.join(PROCESSED_DIR, proc)
        assert os.path.exists(proc_path), f"Processed file '{proc}' referenced in manifest does not exist in {PROCESSED_DIR}."

        actual_checksum = get_sha256(proc_path)
        assert chk == actual_checksum, f"Checksum mismatch for '{proc}'. Expected (from manifest): {chk}, Actual: {actual_checksum}"

    assert manifest_originals == EXPECTED_ORIGINAL_FILES, f"Manifest 'original' files do not match expected. Expected: {EXPECTED_ORIGINAL_FILES}, Found: {manifest_originals}"
    assert manifest_processed == EXPECTED_PROCESSED_FILES, f"Manifest 'processed' files do not match expected. Expected: {EXPECTED_PROCESSED_FILES}, Found: {manifest_processed}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
