#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import json
import hashlib
import tarfile
import glob
import subprocess
import pytest

SOURCE_DIR = "/home/user/source_data"
SCRIPT_PATH = "/home/user/secure_backup.py"
MANIFEST_PATH = "/home/user/manifest.json"
BACKUP_TAR_PATH = "/home/user/backup.tar"
BACKUP_HASH_PATH = "/home/user/backup_hash.txt"
CHUNK_PREFIX = "/home/user/backup.tar.chunk"
CHUNK_SIZE = 512000

def get_file_hash(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for block in iter(lambda: f.read(65536), b''):
            sha256.update(block)
    return sha256.hexdigest()

def get_stream_hash(stream):
    sha256 = hashlib.sha256()
    for block in iter(lambda: stream.read(65536), b''):
        sha256.update(block)
    return sha256.hexdigest()

def test_script_exists_and_runs():
    assert os.path.isfile(SCRIPT_PATH), f"Required Python script {SCRIPT_PATH} is missing."
    try:
        result = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("secure_backup.py did not finish within 120 seconds.")
    assert result.returncode == 0, (
        f"secure_backup.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

def test_manifest_exists_and_correct():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} is missing."

    with open(MANIFEST_PATH, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Manifest is not valid JSON.")

    assert isinstance(manifest, dict), "Manifest should be a JSON dictionary."

    # Compute actual hashes
    actual_hashes = {}
    for root, _, files in os.walk(SOURCE_DIR):
        for file in files:
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, SOURCE_DIR)
            actual_hashes[rel_path] = get_file_hash(full_path)

    assert len(manifest) == len(actual_hashes), "Manifest does not contain the correct number of files."

    for rel_path, expected_hash in actual_hashes.items():
        assert rel_path in manifest, f"File {rel_path} missing from manifest."
        assert manifest[rel_path] == expected_hash, f"Hash mismatch for {rel_path}."

def test_backup_tar_exists_and_contents():
    assert os.path.isfile(BACKUP_TAR_PATH), f"Tar archive {BACKUP_TAR_PATH} is missing."

    expected_files = []
    for root, _, files in os.walk(SOURCE_DIR):
        for file in files:
            full_path = os.path.join(root, file)
            expected_files.append(os.path.relpath(full_path, SOURCE_DIR))

    with tarfile.open(BACKUP_TAR_PATH, 'r') as tar:
        tar_members = [m.name for m in tar.getmembers() if m.isfile()]

    for expected in expected_files:
        # Check if the exact path exists or with a leading './'
        assert expected in tar_members or f"./{expected}" in tar_members, f"File {expected} missing from tar archive or has incorrect path structure."

    # Verify that the archive's regular files correspond exactly to source_data,
    # and that every archived file contains the same bytes as its source file.
    expected_set = set(expected_files)
    with tarfile.open(BACKUP_TAR_PATH, 'r') as tar:
        archived = {}
        for member in tar.getmembers():
            if not member.isfile():
                continue
            normalized_name = member.name[2:] if member.name.startswith("./") else member.name
            assert normalized_name in expected_set, f"Unexpected regular file {member.name} in tar archive."
            assert normalized_name not in archived, f"Duplicate regular file {member.name} in tar archive."
            archived[normalized_name] = member

        assert set(archived) == expected_set, "Tar archive regular-file set does not match source_data."

        for rel_path in expected_files:
            member = archived[rel_path]
            source_path = os.path.join(SOURCE_DIR, rel_path)
            assert member.size == os.path.getsize(source_path), f"Size mismatch for archived file {rel_path}."
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archived file {rel_path}."
            with extracted:
                archived_hash = get_stream_hash(extracted)
            assert archived_hash == get_file_hash(source_path), f"Content mismatch for archived file {rel_path}."

def test_backup_hash_correct():
    assert os.path.isfile(BACKUP_HASH_PATH), f"Hash file {BACKUP_HASH_PATH} is missing."
    assert os.path.isfile(BACKUP_TAR_PATH), f"Tar archive {BACKUP_TAR_PATH} is missing."

    actual_tar_hash = get_file_hash(BACKUP_TAR_PATH)

    with open(BACKUP_HASH_PATH, 'r') as f:
        recorded_hash = f.read().strip()

    assert recorded_hash == actual_tar_hash, "The hash in backup_hash.txt does not match the actual SHA-256 of backup.tar."

def test_chunks_exist_and_correct():
    assert os.path.isfile(BACKUP_TAR_PATH), f"Tar archive {BACKUP_TAR_PATH} is missing."

    chunk_files = sorted(glob.glob(f"{CHUNK_PREFIX}*"))
    assert len(chunk_files) > 0, "No chunk files found."

    total_size = 0
    for i, chunk_file in enumerate(chunk_files):
        size = os.path.getsize(chunk_file)
        total_size += size
        if i < len(chunk_files) - 1:
            assert size == CHUNK_SIZE, f"Chunk {chunk_file} has incorrect size: {size} (expected {CHUNK_SIZE})."

    original_size = os.path.getsize(BACKUP_TAR_PATH)
    assert total_size == original_size, f"Total size of chunks ({total_size}) does not match original tar size ({original_size})."

    # Reconstruct and verify hash
    reconstructed_hash = hashlib.sha256()
    for chunk_file in chunk_files:
        with open(chunk_file, 'rb') as f:
            for block in iter(lambda: f.read(65536), b''):
                reconstructed_hash.update(block)

    actual_tar_hash = get_file_hash(BACKUP_TAR_PATH)
    assert reconstructed_hash.hexdigest() == actual_tar_hash, "Reconstructed tarball hash does not match original backup.tar hash."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
