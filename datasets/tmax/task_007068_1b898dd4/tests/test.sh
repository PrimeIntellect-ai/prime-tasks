#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import hashlib
import zipfile
import pytest

PROJECT_BLOBS_DIR = "/home/user/project_blobs"
ORGANIZED_ZIPS_DIR = "/home/user/organized_zips"
MANIFEST_FILE = "/home/user/zip_manifest.txt"

EXPECTED_SOURCE_FILES = {
    "dir1/blobA.dat",
    "dir1/blobC.zip",
    "dir1/fake.zip",
    "dir2/blobB",
    "dir2/random.dat",
    "dir2/nested/blobA_copy.bin",
}

EXPECTED_ZIP_CONTENTS = {
    "dir1/blobA.dat": ("f1.txt", b"content1\n"),
    "dir2/nested/blobA_copy.bin": ("f1.txt", b"content1\n"),
    "dir2/blobB": ("f2.txt", b"different content\n"),
    "dir1/blobC.zip": ("f3.txt", b"more content\n"),
}

def get_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)
    return sha256.hexdigest()

def get_expected_zips():
    expected_zips = {}
    for root, _, files in os.walk(PROJECT_BLOBS_DIR):
        for file in files:
            filepath = os.path.join(root, file)
            try:
                with open(filepath, "rb") as f:
                    header = f.read(4)
                if header == b'\x50\x4b\x03\x04':
                    checksum = get_sha256(filepath)
                    stat_result = os.stat(filepath)
                    size = stat_result.st_size
                    inode = stat_result.st_ino
                    if checksum not in expected_zips:
                        expected_zips[checksum] = {
                            "size": size,
                            "inodes": set()
                        }
                    expected_zips[checksum]["inodes"].add(inode)
            except Exception:
                pass
    return expected_zips

def test_source_fixtures_remain_intact():
    actual_files = set()
    for root, _, files in os.walk(PROJECT_BLOBS_DIR):
        for filename in files:
            actual_files.add(os.path.relpath(os.path.join(root, filename), PROJECT_BLOBS_DIR))

    assert actual_files == EXPECTED_SOURCE_FILES, \
        f"Source fixture files were added, removed, or renamed. Expected {sorted(EXPECTED_SOURCE_FILES)}, got {sorted(actual_files)}."

    zip_hashes = {}
    for relative_path, (member_name, expected_content) in EXPECTED_ZIP_CONTENTS.items():
        filepath = os.path.join(PROJECT_BLOBS_DIR, relative_path)
        mode = os.lstat(filepath).st_mode
        assert stat.S_ISREG(mode), f"Source fixture {relative_path} is not a regular file."
        with open(filepath, "rb") as f:
            assert f.read(4) == b'\x50\x4b\x03\x04', \
                f"Source ZIP fixture {relative_path} no longer has its original ZIP header."
        try:
            with zipfile.ZipFile(filepath, "r") as archive:
                assert archive.namelist() == [member_name], \
                    f"Source ZIP fixture {relative_path} has unexpected members."
                assert archive.read(member_name) == expected_content, \
                    f"Source ZIP fixture {relative_path} has modified content."
                assert archive.testzip() is None, \
                    f"Source ZIP fixture {relative_path} is corrupt."
        except zipfile.BadZipFile as exc:
            pytest.fail(f"Source ZIP fixture {relative_path} is corrupt: {exc}")
        zip_hashes[relative_path] = get_sha256(filepath)

    assert zip_hashes["dir1/blobA.dat"] == zip_hashes["dir2/nested/blobA_copy.bin"], \
        "The supplied duplicate ZIP fixtures are no longer byte-identical."
    assert len(set(zip_hashes.values())) == 3, \
        "The supplied ZIP fixtures no longer contain exactly three unique archives."

    fake_zip = os.path.join(PROJECT_BLOBS_DIR, "dir1/fake.zip")
    assert os.path.isfile(fake_zip) and not os.path.islink(fake_zip)
    with open(fake_zip, "rb") as f:
        assert f.read() == b"I am just a text file but named like a zip\n", \
            "The supplied fake ZIP fixture was modified."

    random_file = os.path.join(PROJECT_BLOBS_DIR, "dir2/random.dat")
    assert os.path.isfile(random_file) and not os.path.islink(random_file)
    assert os.path.getsize(random_file) == 1024, "The supplied random binary fixture was modified."
    with open(random_file, "rb") as f:
        assert f.read(4) != b'\x50\x4b\x03\x04', \
            "The supplied non-ZIP fixture was changed into a ZIP candidate."

def test_organized_zips_directory_exists():
    assert os.path.isdir(ORGANIZED_ZIPS_DIR), f"The directory {ORGANIZED_ZIPS_DIR} does not exist."

def test_organized_zips_contents_and_hard_links():
    expected_zips = get_expected_zips()

    assert len(expected_zips) > 0, "No valid ZIP files found in the source directory."

    files_in_organized = os.listdir(ORGANIZED_ZIPS_DIR)
    assert len(files_in_organized) == len(expected_zips), \
        f"Expected {len(expected_zips)} files in {ORGANIZED_ZIPS_DIR}, but found {len(files_in_organized)}."

    for filename in files_in_organized:
        assert filename.endswith(".zip"), f"File {filename} in {ORGANIZED_ZIPS_DIR} does not end with .zip"
        checksum = filename[:-4]
        assert checksum in expected_zips, f"File {filename} has an unexpected checksum name."

        filepath = os.path.join(ORGANIZED_ZIPS_DIR, filename)
        stat_result = os.stat(filepath)

        # Verify it's a hard link to one of the original files
        assert stat_result.st_ino in expected_zips[checksum]["inodes"], \
            f"File {filename} is not a hard link to the original file (inode mismatch)."

def test_manifest_file_correctness():
    assert os.path.isfile(MANIFEST_FILE), f"The manifest file {MANIFEST_FILE} does not exist."

    expected_zips = get_expected_zips()
    expected_lines = []
    for checksum, info in expected_zips.items():
        expected_lines.append(f"{checksum} {info['size']}")
    expected_lines.sort()

    with open(MANIFEST_FILE, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, \
        f"The contents of {MANIFEST_FILE} do not match the expected output. " \
        f"Expected: {expected_lines}, Actual: {actual_lines}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
