#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import fcntl
import json
import os
import posixpath
import re
import shutil
import subprocess
import tarfile
import tempfile
import uuid
import pytest

SOURCE_PATH = "/home/user/backup_tool.go"
BINARY_PATH = "/home/user/backup_tool"
ARCHIVE_PATH = "/home/user/backup_archive.tar.gz"
LOCK_PATH = "/home/user/backup.lock"
MANIFEST_PATH = "/home/user/config_manager/manifest.json"
DATA_PATH = "/home/user/config_manager/data"


def test_backup_tool_exists_and_uses_locking():
    source_file = SOURCE_PATH
    assert os.path.isfile(source_file), f"Go source file {source_file} is missing."

    with open(source_file, "r") as f:
        content = f.read()

    # Check for some form of file locking mentioning the lock file
    assert "backup.lock" in content, "The code does not reference backup.lock."

    # Look for common locking mechanisms in Go (syscall.Flock, flock, etc.)
    lock_pattern = re.compile(r'(Flock|flock|Lock|lock)')
    assert lock_pattern.search(content), "No file locking mechanism found in the Go source code."

    assert os.path.isfile(BINARY_PATH), f"Compiled backup tool {BINARY_PATH} is missing."
    assert os.access(BINARY_PATH, os.X_OK), f"Compiled backup tool {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as binary:
        assert binary.read(4) == b"\x7fELF", f"{BINARY_PATH} is not a compiled ELF executable."


def test_backup_archive_exists():
    archive_path = ARCHIVE_PATH
    assert os.path.isfile(archive_path), f"Archive {archive_path} was not created."
    assert tarfile.is_tarfile(archive_path), f"{archive_path} is not a valid tar archive."


def test_backup_archive_contents_and_redaction():
    archive_path = ARCHIVE_PATH

    # We will extract into memory to check contents
    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()

        # Check for infinite loops by counting members
        assert len(members) < 50, "Tarball contains too many files, indicating an infinite symlink loop."

        # Get all file paths in the tarball
        member_names = [m.name for m in members]

        # Ensure paths are relative (e.g., app1/settings.csv, not /home/user/.../app1/settings.csv)
        for name in member_names:
            assert not name.startswith("/home/user"), f"Path {name} in tarball is absolute, should be relative."
            assert not name.startswith("/"), f"Path {name} in tarball is absolute, should be relative."

        # Verify expected files exist
        expected_csv1 = "app1/settings.csv"
        expected_csv2 = "app2/users.csv"

        # Sometimes paths might be prefixed with './'
        csv1_member = next((m for m in members if m.name.endswith(expected_csv1)), None)
        csv2_member = next((m for m in members if m.name.endswith(expected_csv2)), None)

        assert csv1_member is not None, f"{expected_csv1} is missing from the archive."
        assert csv2_member is not None, f"{expected_csv2} is missing from the archive."

        # Verify redaction in app1/settings.csv
        f1 = tar.extractfile(csv1_member)
        content1 = f1.read().decode('utf-8')
        assert "SECRET_KEY=REDACTED" in content1, "Redaction failed in app1/settings.csv."
        assert "9876QWERTY" not in content1, "Original secret still present in app1/settings.csv."

        # Verify redaction in app2/users.csv
        f2 = tar.extractfile(csv2_member)
        content2 = f2.read().decode('utf-8')
        assert content2.count("SECRET_KEY=REDACTED") == 2, "Redaction failed or incomplete in app2/users.csv."
        assert "admin123XYZ" not in content2, "Original secret still present in app2/users.csv."
        assert "guest000" not in content2, "Original secret still present in app2/users.csv."


def test_symlink_loop_avoidance_in_tarball():
    archive_path = ARCHIVE_PATH

    with tarfile.open(archive_path, "r:gz") as tar:
        member_names = [m.name for m in tar.getmembers()]

        # If loops were followed infinitely, we'd see deeply nested paths
        # e.g., app1/loop_to_app2/loop_to_app1/loop_to_app2...
        for name in member_names:
            loop_count = name.count("loop_to_app")
            assert loop_count <= 2, f"Found deeply nested symlink path: {name}. Loop avoidance failed."


def test_executable_lock_contention_and_dynamic_manifest_traversal():
    # A held advisory lock must make the executable fail before producing an archive.
    saved_archive = None
    if os.path.exists(ARCHIVE_PATH):
        saved_archive = tempfile.mktemp(prefix="saved-backup-", dir="/tmp")
        os.replace(ARCHIVE_PATH, saved_archive)

    lock_file = open(LOCK_PATH, "a+")
    try:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        result = subprocess.run(
            [BINARY_PATH], cwd="/home/user", stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=5
        )
        assert result.returncode != 0, "Backup tool succeeded while backup.lock was held."
        assert not os.path.exists(ARCHIVE_PATH), "Backup tool wrote an archive without acquiring the lock."
    finally:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_file.close()
        if os.path.exists(ARCHIVE_PATH):
            os.remove(ARCHIVE_PATH)
        if saved_archive is not None:
            os.replace(saved_archive, ARCHIVE_PATH)

    # Replace the known fixture with unpredictable content and a manifest selecting
    # only one subtree. This requires executing the tool, parsing the manifest,
    # traversing nested files, including JSON, and performing real CSV redaction.
    token = uuid.uuid4().hex
    saved_data = tempfile.mktemp(prefix="saved-data-", dir="/tmp")
    saved_manifest = open(MANIFEST_PATH, "rb").read()
    saved_archive = None
    if os.path.exists(ARCHIVE_PATH):
        saved_archive = tempfile.mktemp(prefix="saved-archive-", dir="/tmp")
        os.replace(ARCHIVE_PATH, saved_archive)
    os.replace(DATA_PATH, saved_data)

    try:
        selected = os.path.join(DATA_PATH, "selected")
        nested = os.path.join(selected, "nested", "deeper")
        decoy = os.path.join(DATA_PATH, "not_in_manifest")
        os.makedirs(nested)
        os.makedirs(decoy)

        csv_name = f"values-{token}.csv"
        json_name = f"config-{token}.json"
        text_name = f"notes-{token}.txt"
        decoy_name = f"decoy-{token}.csv"

        csv_original = (
            "id,value\n"
            f"1,SECRET_KEY={token}A1\n"
            f"2,prefix SECRET_KEY=B2{token} suffix\n"
            "3,ordinary\n"
        )
        csv_expected = re.sub(r"SECRET_KEY=[A-Za-z0-9]+", "SECRET_KEY=REDACTED", csv_original)
        json_content = json.dumps({"token": token, "enabled": True}, sort_keys=True) + "\n"
        text_content = f"non-csv SECRET_KEY={token} must remain unchanged\n"

        with open(os.path.join(nested, csv_name), "w") as f:
            f.write(csv_original)
        with open(os.path.join(selected, json_name), "w") as f:
            f.write(json_content)
        with open(os.path.join(selected, text_name), "w") as f:
            f.write(text_content)
        with open(os.path.join(decoy, decoy_name), "w") as f:
            f.write(f"SECRET_KEY={token}\n")

        # This directory symlink creates a cycle selected/nested/back_to_selected/...
        os.symlink(selected, os.path.join(selected, "nested", "back_to_selected"))

        with open(MANIFEST_PATH, "w") as f:
            json.dump({"targets": [selected]}, f)

        result = subprocess.run(
            [BINARY_PATH], cwd="/home/user", stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=15
        )
        assert result.returncode == 0, (
            "Backup tool failed on dynamic input: "
            + result.stderr.decode("utf-8", errors="replace")
        )
        assert os.path.isfile(ARCHIVE_PATH), "Executing the backup tool did not create the archive."

        expected_csv = f"selected/nested/deeper/{csv_name}"
        expected_json = f"selected/{json_name}"
        expected_text = f"selected/{text_name}"
        forbidden_decoy = f"not_in_manifest/{decoy_name}"

        with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
            members = tar.getmembers()
            assert len(members) < 40, "Dynamic symlink cycle produced excessive archive entries."
            normalized = {}
            for member in members:
                name = posixpath.normpath(member.name)
                assert not member.name.startswith("/"), f"Absolute archive path found: {member.name}"
                assert name != ".." and not name.startswith("../"), f"Escaping archive path found: {member.name}"
                normalized[name] = member

            assert expected_csv in normalized, f"Traversed CSV {expected_csv} is missing."
            assert expected_json in normalized, f"JSON file {expected_json} is missing."
            assert expected_text in normalized, f"Text file {expected_text} is missing."
            assert forbidden_decoy not in normalized, "A file outside the manifest target was archived."

            def read_member(name):
                member = normalized[name]
                assert member.isfile(), f"Expected {name} to be a regular archived file."
                extracted = tar.extractfile(member)
                assert extracted is not None
                return extracted.read().decode("utf-8")

            assert read_member(expected_csv) == csv_expected, "Dynamic CSV redaction was incorrect."
            assert read_member(expected_json) == json_content, "Dynamic JSON file was not preserved."
            assert read_member(expected_text) == text_content, "Non-CSV file was unexpectedly transformed."
    finally:
        if os.path.lexists(DATA_PATH):
            shutil.rmtree(DATA_PATH)
        os.replace(saved_data, DATA_PATH)
        with open(MANIFEST_PATH, "wb") as f:
            f.write(saved_manifest)
        if os.path.exists(ARCHIVE_PATH):
            os.remove(ARCHIVE_PATH)
        if saved_archive is not None:
            os.replace(saved_archive, ARCHIVE_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
