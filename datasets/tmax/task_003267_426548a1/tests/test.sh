#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import pytest

CLEAN_DOCS_DIR = "/home/user/clean_docs"
RAW_ASSETS_DIR = "/home/user/raw_assets"
MANIFEST_PATH = os.path.join(CLEAN_DOCS_DIR, "manifest.sha256")

EXPECTED_PUBLISHED = {
    "system_setup_guide": ["doc_101.md", "img_101.bin"],
    "user_manual_v2": ["doc_103.md", "img_103.bin"],
}

EXPECTED_DRAFTS = {
    "internal_draft_api": ["doc_102.md", "img_102.bin"],
}

def get_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)
    return sha256.hexdigest()

def test_directories_and_files_exist():
    """Verify that the published directories and files are correctly created and copied."""
    for folder, files in EXPECTED_PUBLISHED.items():
        folder_path = os.path.join(CLEAN_DOCS_DIR, folder)
        assert os.path.isdir(folder_path), f"Expected directory {folder_path} is missing."

        for file in files:
            file_path = os.path.join(folder_path, file)
            assert os.path.isfile(file_path), f"Expected file {file_path} is missing."

            # Verify file content matches original
            raw_path = os.path.join(RAW_ASSETS_DIR, file)
            assert get_sha256(file_path) == get_sha256(raw_path), f"Content of {file_path} does not match original {raw_path}."

def test_draft_files_not_copied():
    """Verify that draft records were ignored."""
    for folder, files in EXPECTED_DRAFTS.items():
        folder_path = os.path.join(CLEAN_DOCS_DIR, folder)
        assert not os.path.exists(folder_path), f"Draft directory {folder_path} should not exist."

    # Also check that the files themselves aren't anywhere in clean_docs
    for root, dirs, files in os.walk(CLEAN_DOCS_DIR):
        for file in files:
            assert file not in ["doc_102.md", "img_102.bin"], f"Draft file {file} found in {root}."

def test_manifest_exists_and_content():
    """Verify the manifest file is created, formatted correctly, and contains accurate hashes."""
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} is missing."

    with open(MANIFEST_PATH, "r") as f:
        manifest_lines = [line.strip() for line in f if line.strip()]

    expected_entries = []
    for folder, files in EXPECTED_PUBLISHED.items():
        for file in files:
            raw_path = os.path.join(RAW_ASSETS_DIR, file)
            file_hash = get_sha256(raw_path)
            rel_path = f"{folder}/{file}"
            expected_entries.append(f"{file_hash}  {rel_path}")

    # Manifest must be sorted alphabetically by relative file path
    expected_entries.sort(key=lambda x: x.split("  ")[1])

    assert len(manifest_lines) == len(expected_entries), f"Manifest has {len(manifest_lines)} lines, expected {len(expected_entries)}."

    for i, (actual, expected) in enumerate(zip(manifest_lines, expected_entries)):
        assert actual == expected, f"Manifest line {i+1} mismatch.\nExpected: '{expected}'\nActual:   '{actual}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
