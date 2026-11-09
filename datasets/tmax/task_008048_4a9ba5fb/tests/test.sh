#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import gzip
import hashlib
import os
import re
import subprocess
import tarfile
import tempfile
from pathlib import PurePosixPath

import pytest

INCOMING = "/home/user/incoming/project.cgar"
OUTPUT = "/home/user/clean_project.cgar"
EXTRACTED = "/home/user/extracted"
CLEAN_SOURCE = "/home/user/clean_source"


def decode_cgar(path):
    """Execute the required rev -> base64 -d -> gzip -d decoding pipeline."""
    with open(path, "rb") as f:
        encoded = f.read()

    rev = subprocess.run(["rev"], input=encoded, capture_output=True)
    assert rev.returncode == 0, f"rev failed for {path}: {rev.stderr.decode(errors='ignore')}"

    b64 = subprocess.run(["base64", "-d"], input=rev.stdout, capture_output=True)
    assert b64.returncode == 0, f"base64 decoding failed for {path}: {b64.stderr.decode(errors='ignore')}"

    gunzip = subprocess.run(["gzip", "-d", "-c"], input=b64.stdout, capture_output=True)
    assert gunzip.returncode == 0, f"gzip decompression failed for {path}: {gunzip.stderr.decode(errors='ignore')}"
    return gunzip.stdout


def safe_extract_tar_bytes(tar_bytes, destination):
    tar_path = os.path.join(destination, "payload.tar")
    with open(tar_path, "wb") as f:
        f.write(tar_bytes)

    with tarfile.open(tar_path, "r:") as tf:
        for member in tf.getmembers():
            path = PurePosixPath(member.name)
            assert not path.is_absolute(), f"Archive contains absolute path: {member.name}"
            assert ".." not in path.parts, f"Archive contains path traversal: {member.name}"
            assert member.isdir() or member.isfile(), f"Archive contains unsupported entry type: {member.name}"
        tf.extractall(destination)
    os.remove(tar_path)


def collect_regular_files(root):
    assert os.path.isdir(root), f"Required directory is missing: {root}"
    result = {}
    for current, dirs, files in os.walk(root):
        for dirname in dirs:
            full = os.path.join(current, dirname)
            assert not os.path.islink(full), f"Unexpected symlinked directory: {full}"
        for filename in files:
            full = os.path.join(current, filename)
            assert not os.path.islink(full), f"Unexpected symlink: {full}"
            assert os.path.isfile(full), f"Unexpected non-regular file: {full}"
            relative = os.path.relpath(full, root).replace(os.sep, "/")
            with open(full, "rb") as f:
                result[relative] = f.read()
    return result


def derive_expected_from_incoming():
    """Derive valid files and converted bytes from the supplied incoming archive."""
    outer_tar = decode_cgar(INCOMING)
    with tempfile.TemporaryDirectory() as tmpdir:
        safe_extract_tar_bytes(outer_tar, tmpdir)
        source_tar = os.path.join(tmpdir, "source_files.tar")
        checksums_file = os.path.join(tmpdir, "checksums.md5")
        assert os.path.isfile(source_tar), "Incoming archive lacks source_files.tar"
        assert os.path.isfile(checksums_file), "Incoming archive lacks checksums.md5"

        with open(source_tar, "rb") as f:
            source_tar_bytes = f.read()
        with open(checksums_file, "rb") as f:
            checksums_bytes = f.read()

        source_dir = os.path.join(tmpdir, "reference_source")
        os.mkdir(source_dir)
        with tarfile.open(source_tar, "r:") as tf:
            for member in tf.getmembers():
                path = PurePosixPath(member.name)
                assert not path.is_absolute() and ".." not in path.parts
                assert member.isfile(), f"Unexpected entry in source_files.tar: {member.name}"
            tf.extractall(source_dir)

        original_files = collect_regular_files(source_dir)
        checksums = {}
        for line in checksums_bytes.decode("utf-8").splitlines():
            match = re.fullmatch(r"([0-9a-fA-F]{32})\s+[ *]?(.+)", line)
            assert match, f"Malformed checksum line in incoming archive: {line!r}"
            checksums[match.group(2)] = match.group(1).lower()

        assert set(checksums) == set(original_files), "Checksums do not cover exactly the incoming source files"

        expected = {}
        corrupted = set()
        for name, raw in original_files.items():
            actual_md5 = hashlib.md5(raw).hexdigest()
            if actual_md5 != checksums[name]:
                corrupted.add(name)
                continue
            expected[name] = raw.decode("cp1251").encode("utf-8")

        assert corrupted, "The incoming data unexpectedly contains no corrupted file"
        return expected, corrupted, source_tar_bytes, checksums_bytes


def test_clean_project_cgar_exists():
    """Test that the final archive was created."""
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing."
    assert not os.path.islink(OUTPUT), f"Output file {OUTPUT} must be a regular file, not a symlink."
    assert os.path.getsize(OUTPUT) > 0, f"Output file {OUTPUT} is empty."


def test_clean_project_cgar_contents():
    """Test that the archive can be decompressed and contains the correct files with correct encoding."""
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing."
    expected, corrupted, _, _ = derive_expected_from_incoming()

    tar_bytes = decode_cgar(OUTPUT)
    with tempfile.TemporaryDirectory() as tmpdir:
        safe_extract_tar_bytes(tar_bytes, tmpdir)
        clean_source_dir = os.path.join(tmpdir, "clean_source")
        assert os.path.isdir(clean_source_dir), "The 'clean_source' directory was not found inside the archive. Ensure you packaged the directory itself."

        archived_files = collect_regular_files(clean_source_dir)
        assert archived_files == expected, "The final archive does not contain exactly the checksum-valid files converted from WINDOWS-1251 to UTF-8."

        fileA = os.path.join(clean_source_dir, "fileA.txt")
        fileB = os.path.join(clean_source_dir, "fileB.txt")
        fileC = os.path.join(clean_source_dir, "fileC.txt")
        assert os.path.isfile(fileA), "fileA.txt is missing from the clean_source directory in the archive."
        assert os.path.isfile(fileB), "fileB.txt is missing from the clean_source directory in the archive."
        assert not os.path.exists(fileC), "fileC.txt was found in the archive, but it should have been deleted because it failed the MD5 checksum verification."

        try:
            with open(fileA, "r", encoding="utf-8") as f:
                contentA = f.read().strip()
        except UnicodeDecodeError:
            pytest.fail("fileA.txt is not valid UTF-8.")
        try:
            with open(fileB, "r", encoding="utf-8") as f:
                contentB = f.read().strip()
        except UnicodeDecodeError:
            pytest.fail("fileB.txt is not valid UTF-8.")

        assert contentA == "Привет, мир! Это файл A.", "fileA.txt content is incorrect after conversion."
        assert contentB == "Тестовая строка для файла B.", "fileB.txt content is incorrect after conversion."
        for name in corrupted:
            assert name not in archived_files, f"Corrupted file {name} remains in the final archive."


def test_required_workflow_state():
    """Verify decoded inputs, deletion/move state, and the on-disk clean_source tree."""
    expected, corrupted, source_tar_bytes, checksums_bytes = derive_expected_from_incoming()

    extracted_source_tar = os.path.join(EXTRACTED, "source_files.tar")
    extracted_checksums = os.path.join(EXTRACTED, "checksums.md5")
    assert os.path.isfile(extracted_source_tar), "source_files.tar was not decoded into /home/user/extracted/."
    assert os.path.isfile(extracted_checksums), "checksums.md5 was not decoded into /home/user/extracted/."
    with open(extracted_source_tar, "rb") as f:
        assert f.read() == source_tar_bytes, "Extracted source_files.tar does not match the incoming archive."
    with open(extracted_checksums, "rb") as f:
        assert f.read() == checksums_bytes, "Extracted checksums.md5 does not match the incoming archive."

    extracted_source = os.path.join(EXTRACTED, "source")
    assert os.path.isdir(extracted_source), "/home/user/extracted/source/ was not created."
    assert collect_regular_files(extracted_source) == {}, "Verified files were not moved out of extracted/source, or corrupted/original files remain there."

    disk_clean_files = collect_regular_files(CLEAN_SOURCE)
    assert disk_clean_files == expected, "/home/user/clean_source does not contain exactly the verified UTF-8 files derived from the incoming archive."
    for name in corrupted:
        assert name not in disk_clean_files, f"Corrupted file {name} was not permanently removed from clean_source."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
