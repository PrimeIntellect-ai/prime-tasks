#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import gzip
import hashlib
import pytest

def test_ignored_files_untouched():
    # readme.txt
    readme_path = "/home/user/repo/docs/readme.txt"
    assert os.path.isfile(readme_path), f"Small file {readme_path} should not be deleted."
    assert os.path.getsize(readme_path) == 500000, f"Small file {readme_path} size was modified."

    # ignored.dat
    ignored_path = "/home/user/repo/ignored.dat"
    assert os.path.isfile(ignored_path), f"File {ignored_path} exactly 1,000,000 bytes should not be deleted."
    assert os.path.getsize(ignored_path) == 1000000, f"File {ignored_path} size was modified."

def test_large_files_deleted():
    assert not os.path.exists("/home/user/repo/app.bin"), "Large file app.bin was not deleted."
    assert not os.path.exists("/home/user/repo/libs/libcore.so"), "Large file libcore.so was not deleted."

def test_chunks_created():
    # app.bin chunks
    for i in range(5):
        chunk_path = f"/home/user/repo/app.bin.part0{i}.gz"
        assert os.path.isfile(chunk_path), f"Expected chunk {chunk_path} is missing."

    # libcore.so chunks
    for i in range(3):
        chunk_path = f"/home/user/repo/libs/libcore.so.part0{i}.gz"
        assert os.path.isfile(chunk_path), f"Expected chunk {chunk_path} is missing."

def verify_compressed_chunks(paths, expected_sizes, expected_hash):
    reconstructed_hash = hashlib.sha256()

    for path, expected_size in zip(paths, expected_sizes):
        actual_size = 0
        try:
            with gzip.open(path, "rb") as chunk:
                while True:
                    data = chunk.read(65536)
                    if not data:
                        break
                    actual_size += len(data)
                    assert actual_size <= expected_size, f"Decompressed chunk {path} is larger than {expected_size} bytes."
                    reconstructed_hash.update(data)
        except (OSError, EOFError) as exc:
            pytest.fail(f"Chunk {path} is not a valid, complete gzip file: {exc}")

        assert actual_size == expected_size, (
            f"Decompressed chunk {path} has size {actual_size}; expected {expected_size}."
        )

    assert reconstructed_hash.hexdigest() == expected_hash, (
        "The ordered decompressed chunks do not reconstruct the original file."
    )

def test_chunks_are_valid_and_reconstruct_originals():
    app_paths = [f"/home/user/repo/app.bin.part0{i}.gz" for i in range(5)]
    lib_paths = [f"/home/user/repo/libs/libcore.so.part0{i}.gz" for i in range(3)]

    expected_app_hash = hashlib.sha256(b'A' * 2500000).hexdigest()
    expected_lib_hash = hashlib.sha256(b'B' * 1200000).hexdigest()

    verify_compressed_chunks(app_paths, [500000] * 5, expected_app_hash)
    verify_compressed_chunks(lib_paths, [500000, 500000, 200000], expected_lib_hash)

def test_manifest_content():
    manifest_path = "/home/user/manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing."

    with open(manifest_path, "r") as f:
        lines = f.read().strip().split('\n')

    # Remove empty lines if any
    lines = [line for line in lines if line.strip()]

    assert len(lines) == 2, f"Expected 2 lines in manifest, found {len(lines)}."

    expected_app_hash = hashlib.sha256(b'A' * 2500000).hexdigest()
    expected_lib_hash = hashlib.sha256(b'B' * 1200000).hexdigest()

    expected_line1 = f"/home/user/repo/app.bin|5|{expected_app_hash}"
    expected_line2 = f"/home/user/repo/libs/libcore.so|3|{expected_lib_hash}"

    assert lines[0] == expected_line1, f"First line of manifest is incorrect. Expected: {expected_line1}, Got: {lines[0]}"
    assert lines[1] == expected_line2, f"Second line of manifest is incorrect. Expected: {expected_line2}, Got: {lines[1]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
