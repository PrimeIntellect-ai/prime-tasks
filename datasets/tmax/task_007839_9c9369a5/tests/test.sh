#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import tarfile
import hashlib
import shutil
import secrets
import string
import subprocess
import zipfile
import pytest

EXTRACTED_DIR = "/home/user/extracted"
NEW_MANIFEST = "/home/user/new_manifest.json"
BACKUP_ARCHIVE = "/home/user/incremental_backup.tar.gz"
CURATOR = "/home/user/curator.go"


def test_zip_slip_prevented():
    assert not os.path.exists("/home/user/evil.sh"), "Zip slip vulnerability allowed extraction of evil.sh to /home/user/"
    assert not os.path.exists("/absolute/evil.txt"), "Zip slip vulnerability allowed extraction of absolute/evil.txt"
    assert not os.path.exists(os.path.join(EXTRACTED_DIR, "evil.sh")), "evil.sh should have been ignored"
    assert not os.path.exists(os.path.join(EXTRACTED_DIR, "absolute", "evil.txt")), "evil.txt should have been ignored"


def test_extracted_and_converted_files():
    expected_files = {
        "valid1.bin": b"Hello",
        "valid2.txt": b"World",
        "subdir/valid3.bin": b"Go",
        "subdir2/valid4.txt": b"NewFile"
    }
    for rel_path, expected_content in expected_files.items():
        abs_path = os.path.join(EXTRACTED_DIR, rel_path)
        assert os.path.isfile(abs_path), f"Expected file {abs_path} does not exist"
        with open(abs_path, "rb") as f:
            content = f.read()
        assert content == expected_content, f"Content of {abs_path} is incorrect. Expected {expected_content}, got {content}"


def test_hex_files_deleted():
    assert not os.path.exists(os.path.join(EXTRACTED_DIR, "valid1.hex")), "valid1.hex was not deleted after conversion"
    assert not os.path.exists(os.path.join(EXTRACTED_DIR, "subdir", "valid3.hex")), "subdir/valid3.hex was not deleted after conversion"


def test_new_manifest_generation():
    assert os.path.isfile(NEW_MANIFEST), f"Manifest file {NEW_MANIFEST} does not exist"
    with open(NEW_MANIFEST, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{NEW_MANIFEST} is not valid JSON")

    expected_hashes = {
        "valid1.bin": hashlib.sha256(b"Hello").hexdigest(),
        "valid2.txt": hashlib.sha256(b"World").hexdigest(),
        "subdir/valid3.bin": hashlib.sha256(b"Go").hexdigest(),
        "subdir2/valid4.txt": hashlib.sha256(b"NewFile").hexdigest()
    }
    for rel_path, expected_hash in expected_hashes.items():
        assert rel_path in manifest, f"{rel_path} is missing from the new manifest"
        assert manifest[rel_path] == expected_hash, f"Hash for {rel_path} is incorrect in the manifest"
    for rel_path in manifest.keys():
        assert rel_path in expected_hashes, f"Unexpected file {rel_path} found in manifest"


def test_incremental_backup_archive():
    assert os.path.isfile(BACKUP_ARCHIVE), f"Backup archive {BACKUP_ARCHIVE} does not exist"
    assert tarfile.is_tarfile(BACKUP_ARCHIVE), f"{BACKUP_ARCHIVE} is not a valid tar archive"
    with tarfile.open(BACKUP_ARCHIVE, "r:gz") as tar:
        members = tar.getnames()
        normalized_members = [os.path.normpath(m) for m in members]
        expected_in_backup = ["subdir/valid3.bin", "subdir2/valid4.txt"]
        for expected in expected_in_backup:
            found = any(m == expected or m.endswith('/' + expected) for m in normalized_members)
            assert found, f"{expected} is missing from the incremental backup"
        not_expected_in_backup = ["valid1.bin", "valid2.txt"]
        for not_expected in not_expected_in_backup:
            found = any(m == not_expected or m.endswith('/' + not_expected) for m in normalized_members)
            assert not found, f"{not_expected} should not be in the incremental backup"


def test_program_on_fresh_randomized_repository():
    assert os.path.isfile(CURATOR), f"Required Go program {CURATOR} does not exist"

    token = ''.join(secrets.choice(string.ascii_lowercase) for _ in range(12))
    root_hex = f"root_{token}.hex"
    root_bin = f"root_{token}.bin"
    text_name = f"note_{token}.txt"
    nested_hex = f"nested_{token}/changed_{token}.hex"
    nested_bin = f"nested_{token}/changed_{token}.bin"
    normalized_zip_name = f"discard_{token}/../kept_{token}/new_{token}.txt"
    normalized_name = f"kept_{token}/new_{token}.txt"

    root_data = secrets.token_bytes(31)
    text_data = secrets.token_bytes(27)
    changed_data = secrets.token_bytes(43)
    new_data = secrets.token_bytes(19)
    escaped_data = secrets.token_bytes(17)

    escaped_path = f"/home/user/escaped_{token}.txt"
    absolute_path = f"/tmp/curator_absolute_{token}.txt"
    for path in (escaped_path, absolute_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    shutil.rmtree(EXTRACTED_DIR, ignore_errors=True)
    os.makedirs(EXTRACTED_DIR)
    for path in (NEW_MANIFEST, BACKUP_ARCHIVE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    with zipfile.ZipFile("/home/user/repository.zip", "w") as archive:
        archive.writestr(root_hex, root_data.hex())
        archive.writestr(text_name, text_data)
        archive.writestr(nested_hex, changed_data.hex())
        archive.writestr(normalized_zip_name, new_data)
        archive.writestr(f"../escaped_{token}.txt", escaped_data)
        archive.writestr(absolute_path, escaped_data)

    previous = {
        root_bin: hashlib.sha256(root_data).hexdigest(),
        text_name: hashlib.sha256(text_data).hexdigest(),
        nested_bin: hashlib.sha256(b"deliberately different prior data").hexdigest()
    }
    with open("/home/user/previous_manifest.json", "w") as f:
        json.dump(previous, f)

    result = subprocess.run(
        ["go", "run", CURATOR],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120
    )
    assert result.returncode == 0, f"go run curator.go failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

    assert not os.path.exists(escaped_path), "Traversal entry escaped /home/user/extracted"
    assert not os.path.exists(absolute_path), "Absolute archive entry was extracted"

    expected_files = {
        root_bin: root_data,
        text_name: text_data,
        nested_bin: changed_data,
        normalized_name: new_data
    }
    actual_files = set()
    for directory, _, files in os.walk(EXTRACTED_DIR):
        for filename in files:
            full_path = os.path.join(directory, filename)
            rel_path = os.path.relpath(full_path, EXTRACTED_DIR).replace(os.sep, "/")
            actual_files.add(rel_path)
            assert os.path.isfile(full_path)
    assert actual_files == set(expected_files), f"Unexpected extracted file set: {actual_files}"

    for rel_path, expected_content in expected_files.items():
        with open(os.path.join(EXTRACTED_DIR, *rel_path.split('/')), "rb") as f:
            assert f.read() == expected_content, f"Incorrect content for {rel_path}"
    assert not os.path.exists(os.path.join(EXTRACTED_DIR, root_hex))
    assert not os.path.exists(os.path.join(EXTRACTED_DIR, *nested_hex.split('/')))

    assert os.path.isfile(NEW_MANIFEST)
    with open(NEW_MANIFEST, "r") as f:
        manifest = json.load(f)
    expected_manifest = {
        path: hashlib.sha256(content).hexdigest()
        for path, content in expected_files.items()
    }
    assert manifest == expected_manifest, f"Manifest did not exactly describe current extracted files: {manifest}"

    expected_backup = {
        nested_bin: changed_data,
        normalized_name: new_data
    }
    assert os.path.isfile(BACKUP_ARCHIVE)
    with tarfile.open(BACKUP_ARCHIVE, "r:gz") as archive:
        members = archive.getmembers()
        normalized = [os.path.normpath(member.name).replace(os.sep, "/") for member in members]
        assert len(normalized) == len(expected_backup), f"Backup contains extra or duplicate members: {normalized}"
        assert set(normalized) == set(expected_backup), f"Incorrect incremental backup members: {normalized}"
        for member, rel_path in zip(members, normalized):
            assert member.isfile(), f"Backup member {member.name} is not a regular file"
            extracted = archive.extractfile(member)
            assert extracted is not None
            assert extracted.read() == expected_backup[rel_path], f"Incorrect archived content for {rel_path}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
