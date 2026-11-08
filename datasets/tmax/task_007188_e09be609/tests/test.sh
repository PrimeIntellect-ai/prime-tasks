#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib

MANIFEST_PATH = "/home/user/manifest.json"
TRUTH_MANIFEST_PATH = "/tmp/truth_manifest.json"
BIN_DIR = "/home/user/artifacts_bin"

def get_file_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def test_manifest_exists():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file not found at {MANIFEST_PATH}"

def test_bin_dir_exists():
    assert os.path.isdir(BIN_DIR), f"Artifacts bin directory not found at {BIN_DIR}"

def test_manifest_content_and_chunks():
    assert os.path.isfile(TRUTH_MANIFEST_PATH), "Truth manifest missing, setup is broken."

    with open(TRUTH_MANIFEST_PATH, "r") as f:
        truth_manifest = json.load(f)

    with open(MANIFEST_PATH, "r") as f:
        try:
            student_manifest = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{MANIFEST_PATH} is not valid JSON."

    assert student_manifest == truth_manifest, "The generated manifest.json does not match the expected structure and hashes."

    # Verify each chunk file actually exists and matches the hash
    for artifact_name, chunks in truth_manifest.items():
        for chunk_name, expected_hash in chunks.items():
            chunk_path = os.path.join(BIN_DIR, chunk_name)
            assert os.path.isfile(chunk_path), f"Expected chunk file {chunk_name} is missing in {BIN_DIR}."

            actual_hash = get_file_sha256(chunk_path)
            assert actual_hash == expected_hash, f"Hash mismatch for {chunk_name}. Expected {expected_hash}, got {actual_hash}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
