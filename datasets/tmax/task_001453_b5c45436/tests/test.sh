#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import gzip
import io
import os
import tarfile
import zipfile
import pytest

EXPECTED_MALICIOUS_PATH = "../../../../home/user/evil.sh"
EXPECTED_CHANGELOG = b"""Commit: 123
Author: Alice
Message: Fixed typos in docs
---
Commit: 124
Author: Bob
Message: Updated security protocols
Files changed: auth.py, login.py
Reviewer: Eve
---
Commit: 125
Author: Charlie
Message: Initial release
"""
EXPECTED_RECORD = b"""Commit: 124
Author: Bob
Message: Updated security protocols
Files changed: auth.py, login.py
Reviewer: Eve"""


def read_bundle_from_receipt():
    receipt = "/home/user/docs_receipt.tar.gz"
    assert os.path.isfile(receipt), f"File missing: {receipt}"
    with tarfile.open(receipt, "r:gz") as tf:
        members = [m for m in tf.getmembers() if m.name == "bundle.zip"]
        assert len(members) == 1, "docs_receipt.tar.gz must contain exactly one bundle.zip"
        extracted = tf.extractfile(members[0])
        assert extracted is not None, "bundle.zip is not a regular archive member"
        return extracted.read()


def read_source_zip():
    data = read_bundle_from_receipt()
    try:
        return zipfile.ZipFile(io.BytesIO(data), "r")
    except Exception as e:
        pytest.fail(f"The nested bundle.zip is invalid: {e}")


def test_source_archive_contents():
    with read_source_zip() as zf:
        names = zf.namelist()
        assert "changelog.log" in names, "bundle.zip does not contain changelog.log"
        assert zf.read("changelog.log") == EXPECTED_CHANGELOG, "Unexpected changelog.log in bundle.zip"
        traversal_names = [name for name in names if name.startswith("../")]
        assert traversal_names == [EXPECTED_MALICIOUS_PATH], "Unexpected path-traversal member list"


def test_malicious_path_txt():
    path = "/home/user/malicious_path.txt"
    assert os.path.exists(path), f"File missing: {path}"
    assert os.path.isfile(path), f"Not a regular file: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "../../../../home/user/evil.sh", f"Incorrect malicious path found: {content}"


def test_changelog_extracted():
    path = "/home/user/changelog.log"
    assert os.path.exists(path), f"File missing: {path}"
    assert os.path.isfile(path), f"Not a regular file: {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "Updated security protocols" in content, "changelog.log does not contain expected content."
    with open(path, "rb") as f:
        actual = f.read()
    with read_source_zip() as zf:
        archived = zf.read("changelog.log")
    assert archived == EXPECTED_CHANGELOG, "The source archive's changelog.log is unexpected"
    assert actual == archived, "changelog.log is not the exact archive member"


def test_target_record_txt():
    path = "/home/user/target_record.txt"
    assert os.path.exists(path), f"File missing: {path}"
    assert os.path.isfile(path), f"Not a regular file: {path}"
    with open(path, "r") as f:
        content = f.read().strip()

    assert "Updated security protocols" in content, "target_record.txt missing expected phrase."
    assert "---" not in content, "target_record.txt should not contain the '---' separators."
    assert "Commit: 124" in content, "target_record.txt missing 'Commit: 124'."
    assert "Commit: 123" not in content, "target_record.txt contains other records."
    assert "Commit: 125" not in content, "target_record.txt contains other records."

    with open(path, "rb") as f:
        actual = f.read()
    assert actual == EXPECTED_RECORD, "target_record.txt is not the exact multi-line matching record"


def test_record_custom_gz():
    record_path = "/home/user/target_record.txt"
    gz_path = "/home/user/record_custom.gz"

    assert os.path.exists(gz_path), f"File missing: {gz_path}"
    assert os.path.isfile(gz_path), f"Not a regular file: {gz_path}"

    with open(record_path, "rb") as f:
        expected_raw = f.read()

    try:
        with gzip.open(gz_path, "rb") as f:
            decompressed_content = f.read()
    except Exception as e:
        pytest.fail(f"Failed to decompress {gz_path}: {e}")

    try:
        decoded_content = base64.b64decode(decompressed_content)
    except Exception as e:
        pytest.fail(f"Failed to base64 decode the decompressed content: {e}")

    assert decoded_content == expected_raw, "The decoded content of the gzipped base64 does not match target_record.txt"
    assert expected_raw == EXPECTED_RECORD, "target_record.txt does not contain the expected record"
    assert decompressed_content == base64.b64encode(EXPECTED_RECORD), \
        "record_custom.gz does not contain the canonical continuous base64 encoding of the exact record"
    try:
        base64.b64decode(decompressed_content, validate=True)
    except Exception as e:
        pytest.fail(f"The decompressed data is not strict standard base64: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
