#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import pytest

RAW_DIR = "/home/user/artifacts/raw"
CHUNKED_DIR = "/home/user/artifacts/chunked"
RESTORED_DIR = "/home/user/artifacts/restored"
LEGACY_CSV = "/home/user/artifacts/legacy_manifest.csv"
MANIFEST_JSON = "/home/user/artifacts/manifest.json"
RESTORED_HASH_TXT = "/home/user/artifacts/restored_hash.txt"
CHUNK_SIZE = 5 * 1024 * 1024

def get_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for block in iter(lambda: f.read(65536), b""):
            sha256.update(block)
    return sha256.hexdigest()

def assert_chunk_matches_raw(chunk_path, raw_path, offset, length):
    with open(raw_path, 'rb') as raw, open(chunk_path, 'rb') as chunk:
        raw.seek(offset)
        remaining = length
        while remaining:
            block_size = min(65536, remaining)
            raw_block = raw.read(block_size)
            chunk_block = chunk.read(block_size)
            assert chunk_block == raw_block, f"Chunk {chunk_path} does not match the corresponding bytes of {raw_path}"
            remaining -= len(raw_block)
            assert len(raw_block) == block_size, f"Unexpected end of raw file {raw_path}"
        assert chunk.read(1) == b"", f"Chunk {chunk_path} contains extra data"

def test_legacy_manifest_csv():
    assert os.path.isfile(LEGACY_CSV), f"Missing converted CSV manifest at {LEGACY_CSV}"

    expected_csv = (
        "filename,hash,date\n"
        "legacy_app.bin,3b9c6f932e6a9f5d,2021-04-12\n"
        "driver_pack.bin,8f4e2d1a0b9c8d7e,2021-08-22\n"
        "old_firmware.bin,1a2b3c4d5e6f7g8h,2022-01-05"
    )

    with open(LEGACY_CSV, 'r') as f:
        content = f.read().strip()

    assert content == expected_csv, "The contents of legacy_manifest.csv do not match the expected output format."

def test_chunked_files_and_sizes():
    assert os.path.isdir(CHUNKED_DIR), f"Missing chunked directory at {CHUNKED_DIR}"

    expected_files = {
        "app_v1.bin": 12 * 1024 * 1024,
        "app_v2.bin": 7 * 1024 * 1024,
        "app_v3.bin": 25 * 1024 * 1024
    }

    for filename, size in expected_files.items():
        num_full_chunks = size // CHUNK_SIZE
        remainder = size % CHUNK_SIZE
        total_chunks = num_full_chunks + (1 if remainder > 0 else 0)
        raw_path = os.path.join(RAW_DIR, filename)

        for i in range(total_chunks):
            chunk_name = f"{filename}.chunk.{i:03d}"
            chunk_path = os.path.join(CHUNKED_DIR, chunk_name)

            assert os.path.isfile(chunk_path), f"Missing chunk file: {chunk_path}"

            actual_size = os.path.getsize(chunk_path)
            expected_chunk_size = CHUNK_SIZE if i < num_full_chunks else remainder

            assert actual_size == expected_chunk_size, f"Chunk {chunk_name} has incorrect size: {actual_size} (expected {expected_chunk_size})"
            assert_chunk_matches_raw(chunk_path, raw_path, i * CHUNK_SIZE, expected_chunk_size)

def test_manifest_json():
    assert os.path.isfile(MANIFEST_JSON), f"Missing JSON manifest at {MANIFEST_JSON}"

    with open(MANIFEST_JSON, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {MANIFEST_JSON} is not valid JSON")

    raw_files = ["app_v1.bin", "app_v2.bin", "app_v3.bin"]

    for raw_file in raw_files:
        assert raw_file in manifest, f"Manifest is missing key for {raw_file}"
        file_info = manifest[raw_file]

        raw_path = os.path.join(RAW_DIR, raw_file)
        expected_raw_hash = get_sha256(raw_path)

        assert "original_sha256" in file_info, f"Manifest missing 'original_sha256' for {raw_file}"
        assert file_info["original_sha256"] == expected_raw_hash, f"Incorrect original_sha256 for {raw_file}"

        assert "chunks" in file_info, f"Manifest missing 'chunks' for {raw_file}"

        # Verify chunks
        raw_size = os.path.getsize(raw_path)
        total_chunks = (raw_size + CHUNK_SIZE - 1) // CHUNK_SIZE

        for i in range(total_chunks):
            chunk_name = f"{raw_file}.chunk.{i:03d}"
            assert chunk_name in file_info["chunks"], f"Manifest missing chunk {chunk_name} for {raw_file}"

            chunk_path = os.path.join(CHUNKED_DIR, chunk_name)
            expected_chunk_hash = get_sha256(chunk_path)

            assert file_info["chunks"][chunk_name] == expected_chunk_hash, f"Incorrect hash for chunk {chunk_name}"

def test_restored_file_and_hash():
    restored_file = os.path.join(RESTORED_DIR, "app_v2.bin")
    raw_file = os.path.join(RAW_DIR, "app_v2.bin")

    assert os.path.isfile(restored_file), f"Missing restored file at {restored_file}"

    expected_hash = get_sha256(raw_file)
    restored_hash = get_sha256(restored_file)

    assert restored_hash == expected_hash, "The restored app_v2.bin does not match the original file."

    assert os.path.isfile(RESTORED_HASH_TXT), f"Missing restored hash file at {RESTORED_HASH_TXT}"

    with open(RESTORED_HASH_TXT, 'r') as f:
        written_hash = f.read().strip()

    assert written_hash == expected_hash, f"The hash in {RESTORED_HASH_TXT} does not match the actual SHA-256 of app_v2.bin."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
