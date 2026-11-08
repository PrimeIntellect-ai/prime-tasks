#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile
import json
import pytest

ARCHIVE_PATH = "/home/user/curated_archive.tar.gz"
REPO_DIR = "/home/user/artifact_repo"

def test_archive_exists():
    assert os.path.isfile(ARCHIVE_PATH), f"Archive {ARCHIVE_PATH} was not created."

def test_archive_contents():
    assert os.path.isfile(ARCHIVE_PATH), f"Archive {ARCHIVE_PATH} is missing."

    expected_files = {
        "curated_artifact_01.dat",
        "artifact_01.json",
        "curated_artifact_03.dat",
        "artifact_03.json"
    }

    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        members = tar.getmembers()

        # Check that there are no extra files or directories
        actual_files = set()
        for member in members:
            assert member.isfile(), f"Archive contains non-file member: {member.name}"
            # Ensure no directory structure (files are at the root)
            assert "/" not in member.name and "\\" not in member.name, f"File {member.name} is not at the root of the archive."
            actual_files.add(member.name)

        assert actual_files == expected_files, f"Archive contents mismatch. Expected {expected_files}, got {actual_files}."

def test_archive_data_contents():
    assert os.path.isfile(ARCHIVE_PATH), f"Archive {ARCHIVE_PATH} is missing."

    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        # Check curated_artifact_01.dat
        f1 = tar.extractfile("curated_artifact_01.dat")
        assert f1 is not None, "curated_artifact_01.dat missing in archive"
        assert b"binary_data_01_A7F3" in f1.read(), "Incorrect content in curated_artifact_01.dat"

        # Check curated_artifact_03.dat
        f3 = tar.extractfile("curated_artifact_03.dat")
        assert f3 is not None, "curated_artifact_03.dat missing in archive"
        assert b"binary_data_03_C9D4" in f3.read(), "Incorrect content in curated_artifact_03.dat"

        # Check artifact_01.json
        j1 = tar.extractfile("artifact_01.json")
        assert j1 is not None, "artifact_01.json missing in archive"
        try:
            data1 = json.load(j1)
        except json.JSONDecodeError:
            pytest.fail("artifact_01.json is not valid JSON")
        assert data1 == {"build": "1042", "status": "success", "module": "auth"}, "Incorrect metadata in artifact_01.json"

        # Check artifact_03.json
        j3 = tar.extractfile("artifact_03.json")
        assert j3 is not None, "artifact_03.json missing in archive"
        try:
            data3 = json.load(j3)
        except json.JSONDecodeError:
            pytest.fail("artifact_03.json is not valid JSON")
        assert data3 == {"build": "1044", "status": "success", "module": "payment"}, "Incorrect metadata in artifact_03.json"

def test_directory_state():
    # Check that original unlocked .dat files were renamed
    assert not os.path.exists(os.path.join(REPO_DIR, "artifact_01.dat")), "artifact_01.dat was not renamed."
    assert not os.path.exists(os.path.join(REPO_DIR, "artifact_03.dat")), "artifact_03.dat was not renamed."

    assert os.path.isfile(os.path.join(REPO_DIR, "curated_artifact_01.dat")), "curated_artifact_01.dat is missing in repo."
    assert os.path.isfile(os.path.join(REPO_DIR, "curated_artifact_03.dat")), "curated_artifact_03.dat is missing in repo."

    assert os.path.isfile(os.path.join(REPO_DIR, "artifact_01.json")), "artifact_01.json is missing in repo."
    assert os.path.isfile(os.path.join(REPO_DIR, "artifact_03.json")), "artifact_03.json is missing in repo."

    # Check that locked artifact 02 was untouched
    assert os.path.isfile(os.path.join(REPO_DIR, "artifact_02.dat")), "Locked artifact_02.dat should not be modified/renamed."
    assert os.path.isfile(os.path.join(REPO_DIR, "artifact_02.meta")), "Locked artifact_02.meta should not be modified/removed."
    assert os.path.isfile(os.path.join(REPO_DIR, "artifact_02.lock")), "Locked artifact_02.lock should not be modified/removed."
    assert not os.path.exists(os.path.join(REPO_DIR, "curated_artifact_02.dat")), "Locked artifact_02.dat should not be processed."
    assert not os.path.exists(os.path.join(REPO_DIR, "artifact_02.json")), "Locked artifact_02.meta should not be processed."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
