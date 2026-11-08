#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import pytest

STAGING_DIR = "/home/user/staging"
MANIFEST_FILE = "/home/user/manifest.txt"

def get_md5(content_bytes):
    return hashlib.md5(content_bytes).hexdigest()

def test_manifest_exists():
    """Verify that the manifest file was generated."""
    assert os.path.isfile(MANIFEST_FILE), f"Manifest file {MANIFEST_FILE} is missing."

def test_no_symlinks():
    """Verify that all symlinks have been removed from the staging directory."""
    symlinks = []
    for root, dirs, files in os.walk(STAGING_DIR):
        for name in dirs + files:
            path = os.path.join(root, name)
            if os.path.islink(path):
                symlinks.append(path)

    assert not symlinks, f"Found symlinks that were not removed: {symlinks}"

def test_no_cst_files():
    """Verify that all .cst files have been removed from the staging directory."""
    cst_files = []
    for root, dirs, files in os.walk(STAGING_DIR):
        for name in files:
            if name.endswith('.cst'):
                cst_files.append(os.path.join(root, name))

    assert not cst_files, f"Found .cst files that were not removed: {cst_files}"

def test_decoded_files_exist_and_correct():
    """Verify that the .dec files and normal files exist and contain the correct data."""
    expected_files = {
        "dir_a/file1.dec": b"hello world",
        "dir_b/file2.dec": b"secret data payload",
        "normal.txt": b"normal text file"
    }

    for rel_path, expected_content in expected_files.items():
        full_path = os.path.join(STAGING_DIR, rel_path)
        assert os.path.isfile(full_path), f"Expected file missing: {full_path}"

        with open(full_path, "rb") as f:
            content = f.read()
        assert content == expected_content, f"Content mismatch in {full_path}. Expected {expected_content}, got {content}"

def test_manifest_content():
    """Verify the contents of the manifest file."""
    assert os.path.isfile(MANIFEST_FILE), "Manifest file is missing."

    expected_data = {
        "dir_a/file1.dec": get_md5(b"hello world"),
        "dir_b/file2.dec": get_md5(b"secret data payload"),
        "normal.txt": get_md5(b"normal text file")
    }

    with open(MANIFEST_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Manifest should have exactly 3 lines, found {len(lines)}"

    parsed_manifest = {}
    for line in lines:
        parts = line.split(None, 1)
        assert len(parts) == 2, f"Malformed line in manifest: '{line}'"
        md5_hash, file_path = parts

        # Normalize path by removing leading './' if present
        if file_path.startswith("./"):
            file_path = file_path[2:]

        parsed_manifest[file_path] = md5_hash

    for rel_path, expected_md5 in expected_data.items():
        assert rel_path in parsed_manifest, f"File {rel_path} missing from manifest."
        assert parsed_manifest[rel_path] == expected_md5, f"MD5 mismatch for {rel_path}. Expected {expected_md5}, got {parsed_manifest[rel_path]}"

def test_manifest_sorting():
    """Verify that the manifest is sorted alphabetically by relative file path."""
    with open(MANIFEST_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    paths = []
    for line in lines:
        parts = line.split(None, 1)
        if len(parts) == 2:
            paths.append(parts[1])

    assert paths == sorted(paths), "Manifest file is not sorted alphabetically by file path."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
