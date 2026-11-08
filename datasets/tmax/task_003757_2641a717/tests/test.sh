#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile
import json
import zipfile
import pytest

SUMMARY_FILE = "/home/user/summary.txt"
TARBALL_FILE = "/home/user/clean_configs.tar.gz"
BACKUPS_DIR = "/home/user/backups"

EXPECTED_FILES = [
    "archive1_valid2.json",
    "loose_valid1.json"
]

def expected_payloads():
    payloads = {}

    loose_path = os.path.join(BACKUPS_DIR, "loose_valid1.json")
    assert os.path.isfile(loose_path), f"Source file {loose_path} is missing."
    with open(loose_path, "rb") as f:
        payloads["loose_valid1.json"] = f.read()

    zip_path = os.path.join(BACKUPS_DIR, "backup1.zip")
    assert os.path.isfile(zip_path), f"Source archive {zip_path} is missing."
    assert zipfile.is_zipfile(zip_path), f"Source archive {zip_path} is not a valid zip file."
    with zipfile.ZipFile(zip_path, "r") as zf:
        assert zf.testzip() is None, f"Source archive {zip_path} failed its integrity check."
        matches = [
            name for name in zf.namelist()
            if not name.endswith("/") and os.path.basename(name) == "archive1_valid2.json"
        ]
        assert len(matches) == 1, (
            f"Expected exactly one archive1_valid2.json in {zip_path}, found {matches}."
        )
        payloads["archive1_valid2.json"] = zf.read(matches[0])

    return payloads

def test_summary_file_exists_and_correct():
    assert os.path.isfile(SUMMARY_FILE), f"The summary file {SUMMARY_FILE} is missing."

    with open(SUMMARY_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == EXPECTED_FILES, (
        f"The contents of {SUMMARY_FILE} do not match the expected list of valid JSON files.\n"
        f"Expected: {EXPECTED_FILES}\n"
        f"Found: {lines}"
    )

def test_tarball_exists_and_contains_correct_files():
    assert os.path.isfile(TARBALL_FILE), f"The tarball {TARBALL_FILE} is missing."
    assert tarfile.is_tarfile(TARBALL_FILE), f"The file {TARBALL_FILE} is not a valid tar archive."

    with tarfile.open(TARBALL_FILE, "r:gz") as tar:
        members = tar.getmembers()

        # Check that all members are regular files
        for member in members:
            assert member.isfile(), f"Tarball contains non-file member: {member.name}"
            assert member.name == os.path.basename(member.name), (
                f"Tarball member is not flattened at the archive root: {member.name}"
            )

        # Extract base filenames, removing any './' prefix or directory paths
        filenames = sorted([os.path.basename(member.name) for member in members])

        assert filenames == EXPECTED_FILES, (
            f"The tarball {TARBALL_FILE} does not contain the exact expected valid JSON files.\n"
            f"Expected: {EXPECTED_FILES}\n"
            f"Found: {filenames}"
        )

def test_tarball_files_are_valid_json():
    # Double check that the files inside the tarball are actually valid JSON
    with tarfile.open(TARBALL_FILE, "r:gz") as tar:
        for member in tar.getmembers():
            f = tar.extractfile(member)
            assert f is not None, f"Could not extract {member.name} from tarball."
            content = f.read().decode('utf-8')
            try:
                json.loads(content)
            except json.JSONDecodeError:
                pytest.fail(f"File {member.name} inside the tarball is not valid JSON.")

def test_tarball_files_match_source_contents():
    expected = expected_payloads()
    with tarfile.open(TARBALL_FILE, "r:gz") as tar:
        actual = {}
        for member in tar.getmembers():
            f = tar.extractfile(member)
            assert f is not None, f"Could not extract {member.name} from tarball."
            actual[member.name] = f.read()

    assert set(actual) == set(expected), (
        f"Archived file names do not match the valid source JSON files: {sorted(actual)}"
    )
    for filename, source_content in expected.items():
        assert actual[filename] == source_content, (
            f"Archived content for {filename} does not match the source JSON file."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
