#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import tarfile
import hashlib
import gzip
import pytest

SOURCE_DIR = "/home/user/data_to_backup"
STAGING_DIR = "/home/user/staging_backup"
MANIFEST_PATH = "/home/user/manifest.txt"
TAR_PATH = "/home/user/final_backup.tar"

def get_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b""):
            h.update(chunk)
    return h.hexdigest()

def test_manifest_exists_and_correct():
    assert os.path.exists(MANIFEST_PATH), f"Manifest file missing at {MANIFEST_PATH}"
    assert os.path.isfile(MANIFEST_PATH), f"{MANIFEST_PATH} is not a file"

    manifest_hashes = {}
    with open(MANIFEST_PATH, 'r') as f:
        for line in f:
            parts = line.strip().split('  ', 1)
            if len(parts) == 2:
                manifest_hashes[parts[1]] = parts[0]

    for root, dirs, files in os.walk(SOURCE_DIR):
        for file in files:
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, SOURCE_DIR)
            expected_hash = get_sha256(full_path)
            assert rel_path in manifest_hashes, f"File {rel_path} missing from manifest"
            assert manifest_hashes[rel_path] == expected_hash, f"Hash mismatch in manifest for {rel_path}"

def test_staging_directory_exists_and_is_populated_correctly():
    assert os.path.exists(STAGING_DIR), f"Staging directory missing at {STAGING_DIR}"
    assert os.path.isdir(STAGING_DIR), f"{STAGING_DIR} is not a directory"
    assert not os.path.islink(STAGING_DIR), f"{STAGING_DIR} must be an actual staging directory"

    expected_dirs = {"."}
    expected_files = set()

    for root, dirs, files in os.walk(SOURCE_DIR):
        rel_root = os.path.relpath(root, SOURCE_DIR)
        expected_dirs.add(rel_root)
        for directory in dirs:
            expected_dirs.add(os.path.normpath(os.path.join(rel_root, directory)))

        for filename in files:
            source_path = os.path.join(root, filename)
            rel_path = os.path.normpath(os.path.join(rel_root, filename))

            if filename.endswith((".log", ".txt")):
                staged_rel_path = rel_path + ".gz"
                expected_files.add(staged_rel_path)
                staged_path = os.path.join(STAGING_DIR, staged_rel_path)
                assert os.path.isfile(staged_path), f"Compressed staging file missing: {staged_rel_path}"
                with gzip.open(staged_path, "rb") as f:
                    staged_data = f.read()
                with open(source_path, "rb") as f:
                    source_data = f.read()
                assert staged_data == source_data, f"Compressed staging file does not match source: {staged_rel_path}"
            elif filename.endswith((".bin", ".dat")):
                expected_files.add(rel_path)
                staged_path = os.path.join(STAGING_DIR, rel_path)
                assert os.path.isfile(staged_path), f"Binary staging file missing: {rel_path}"
                assert get_sha256(staged_path) == get_sha256(source_path), f"Binary staging file does not match source: {rel_path}"

    actual_dirs = {"."}
    actual_files = set()
    for root, dirs, files in os.walk(STAGING_DIR):
        rel_root = os.path.relpath(root, STAGING_DIR)
        actual_dirs.add(rel_root)
        for directory in dirs:
            actual_dirs.add(os.path.normpath(os.path.join(rel_root, directory)))
        for filename in files:
            actual_files.add(os.path.normpath(os.path.join(rel_root, filename)))

    assert actual_dirs == expected_dirs, "Staging directory structure does not exactly match the source structure"
    assert actual_files == expected_files, "Staging directory files do not exactly match the required transformed files"

def test_tar_exists():
    assert os.path.exists(TAR_PATH), f"Tar file missing at {TAR_PATH}"
    assert os.path.isfile(TAR_PATH), f"{TAR_PATH} is not a file"
    assert tarfile.is_tarfile(TAR_PATH), f"{TAR_PATH} is not a valid tar archive"

def test_tar_contents_and_integrity(tmp_path):
    assert os.path.exists(TAR_PATH), "Tar file is missing, cannot test contents"

    with tarfile.open(TAR_PATH, 'r') as tar:
        names = tar.getnames()

        # Check required files exist in tar
        expected_files = [
            'manifest.txt',
            'logs/auth.log.gz',
            'logs/app.log.gz',
            'configs/db.txt.gz',
            'binaries/core.bin',
            'binaries/old_fw/v1.dat'
        ]

        for ef in expected_files:
            assert ef in names, f"Expected file {ef} is missing from the tar archive"

        # Extract everything to a temp dir for verification
        tar.extractall(path=tmp_path)

    # Verify manifest.txt matches
    extracted_manifest = tmp_path / "manifest.txt"
    assert os.path.exists(extracted_manifest), "manifest.txt not extracted"
    assert get_sha256(extracted_manifest) == get_sha256(MANIFEST_PATH), "manifest.txt in tar does not match the original manifest.txt"

    # Verify binary files are identical
    binaries = ['binaries/core.bin', 'binaries/old_fw/v1.dat']
    for b in binaries:
        orig_path = os.path.join(SOURCE_DIR, b)
        extr_path = tmp_path / b
        assert os.path.exists(extr_path), f"Extracted binary {b} missing"
        assert get_sha256(extr_path) == get_sha256(orig_path), f"Extracted binary {b} does not match original"

    # Verify text files were compressed correctly
    text_files = [
        ('logs/auth.log', 'logs/auth.log.gz'),
        ('logs/app.log', 'logs/app.log.gz'),
        ('configs/db.txt', 'configs/db.txt.gz')
    ]

    for orig, gz_name in text_files:
        orig_path = os.path.join(SOURCE_DIR, orig)
        extr_path = tmp_path / gz_name
        assert os.path.exists(extr_path), f"Extracted compressed file {gz_name} missing"

        with gzip.open(extr_path, 'rb') as f:
            decompressed_data = f.read()

        with open(orig_path, 'rb') as f:
            orig_data = f.read()

        assert decompressed_data == orig_data, f"Decompressed content of {gz_name} does not match original {orig}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
