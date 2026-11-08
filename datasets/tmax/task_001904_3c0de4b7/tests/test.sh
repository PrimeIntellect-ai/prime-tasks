#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import hashlib
import tarfile
import pytest

PROJECT_DIR = "/home/user/project"
EXTRACTED_DIR = os.path.join(PROJECT_DIR, "extracted")
MANIFEST_PATH = os.path.join(PROJECT_DIR, "manifest.csv")
RELEASE_PATH = os.path.join(PROJECT_DIR, "release.tar.gz")

EXPECTED_FILES = {
    "config.json": {
        "content": b'{"version":1,"debug":1}',
        "sha256": "3a42c4b82d3ffb4a0db8bd6c813be6cece00435160bb4fdbfb78b88ce8e65df6",
        "size": 22
    },
    "firmware.elf": {
        "content": b'\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00',
        "sha256": "24b9148bcf7b2bb2b0bc8c6a01ba262b9a78129e71eab078832a5df09aa1113c",
        "size": 16
    }
}

def test_extracted_directory_exists():
    assert os.path.isdir(EXTRACTED_DIR), f"The directory {EXTRACTED_DIR} does not exist."

def test_extracted_files_content_and_hash():
    for filename, expected in EXPECTED_FILES.items():
        filepath = os.path.join(EXTRACTED_DIR, filename)
        assert os.path.isfile(filepath), f"The file {filepath} does not exist."

        with open(filepath, "rb") as f:
            content = f.read()

        assert len(content) == expected["size"], f"File {filename} size mismatch. Expected {expected['size']}, got {len(content)}."
        assert content == expected["content"], f"File {filename} content mismatch."

        file_hash = hashlib.sha256(content).hexdigest()
        assert file_hash == expected["sha256"], f"File {filename} hash mismatch."

def test_manifest_csv_exists_and_content():
    assert os.path.isfile(MANIFEST_PATH), f"The file {MANIFEST_PATH} does not exist."

    with open(MANIFEST_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected 2 lines in manifest.csv, found {len(lines)}."

    manifest_data = {}
    for line in lines:
        parts = line.split(',')
        assert len(parts) == 2, f"Invalid format in manifest.csv line: '{line}'"
        manifest_data[parts[0]] = parts[1]

    for filename, expected in EXPECTED_FILES.items():
        assert filename in manifest_data, f"{filename} missing from manifest.csv."
        assert manifest_data[filename] == expected["sha256"], f"Hash mismatch in manifest.csv for {filename}."

def normalized_tar_name(name):
    while name.startswith("./"):
        name = name[2:]
    return name.rstrip("/")

def test_release_tarball_exists_and_valid():
    assert os.path.isfile(RELEASE_PATH), f"The file {RELEASE_PATH} does not exist."
    assert tarfile.is_tarfile(RELEASE_PATH), f"{RELEASE_PATH} is not a valid tar archive."

    with tarfile.open(RELEASE_PATH, "r:gz") as tar:
        names = tar.getnames()

        manifest_found = any(name.endswith("manifest.csv") for name in names)
        assert manifest_found, "manifest.csv not found in the tarball."

        config_found = any(name.endswith("config.json") for name in names)
        firmware_found = any(name.endswith("firmware.elf") for name in names)

        assert config_found, "config.json not found in the tarball."
        assert firmware_found, "firmware.elf not found in the tarball."

        members = {}
        for member in tar.getmembers():
            normalized = normalized_tar_name(member.name)
            if normalized in {"manifest.csv", "extracted", "extracted/config.json", "extracted/firmware.elf"}:
                assert normalized not in members, f"Duplicate archive member: {normalized}"
                members[normalized] = member

        assert "manifest.csv" in members, "manifest.csv is not stored at the required archive path."
        assert "extracted" in members and members["extracted"].isdir(), "extracted/ directory is missing from the tarball."
        assert "extracted/config.json" in members, "extracted/config.json is missing from the tarball."
        assert "extracted/firmware.elf" in members, "extracted/firmware.elf is missing from the tarball."

        with open(MANIFEST_PATH, "rb") as f:
            expected_manifest = f.read()
        archived_manifest = tar.extractfile(members["manifest.csv"])
        assert archived_manifest is not None
        assert archived_manifest.read() == expected_manifest, "Archived manifest.csv content does not match manifest.csv."

        for filename, expected in EXPECTED_FILES.items():
            member = members[f"extracted/{filename}"]
            archived_file = tar.extractfile(member)
            assert archived_file is not None
            assert archived_file.read() == expected["content"], f"Archived {filename} content mismatch."
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_extractor_dynamic.py
import json
import os
import shutil
import subprocess
import tempfile
import uuid

project = "/home/user/project"
archive = os.path.join(project, "archive.pack")
extracted = os.path.join(project, "extracted")
binary = "/tmp/extractor_under_test"

with tempfile.TemporaryDirectory() as backup:
    archive_backup = os.path.join(backup, "archive.pack")
    extracted_backup = os.path.join(backup, "extracted")
    shutil.copy2(archive, archive_backup)
    if os.path.exists(extracted):
        shutil.copytree(extracted, extracted_backup)

    try:
        token = uuid.uuid4().hex
        payloads = {
            f"alpha_{token}.bin": os.urandom(31),
            f"beta_{token}.dat": os.urandom(47),
        }
        entries = []
        offset = 0
        for name, content in payloads.items():
            entries.append({"name": name, "offset": offset, "size": len(content)})
            offset += len(content)

        header = json.dumps({"files": entries}, separators=(",", ":")).encode("utf-8")
        with open(archive, "wb") as f:
            f.write(header)
            f.write(b"\0")
            for content in payloads.values():
                f.write(content)

        if os.path.lexists(extracted):
            if os.path.isdir(extracted) and not os.path.islink(extracted):
                shutil.rmtree(extracted)
            else:
                os.unlink(extracted)

        subprocess.run([binary], cwd=project, check=True, timeout=15)
        assert os.path.isdir(extracted), "Extractor did not create extracted/."

        actual_files = set()
        for root, dirs, files in os.walk(extracted):
            for filename in files:
                actual_files.add(os.path.relpath(os.path.join(root, filename), extracted))
        assert actual_files == set(payloads), "Extractor produced the wrong files for a generated archive."

        for name, expected in payloads.items():
            path = os.path.join(extracted, name)
            assert os.path.isfile(path), f"Extractor did not create {name}."
            with open(path, "rb") as f:
                assert f.read() == expected, f"Extractor produced incorrect content for {name}."
    finally:
        shutil.copy2(archive_backup, archive)
        if os.path.lexists(extracted):
            if os.path.isdir(extracted) and not os.path.islink(extracted):
                shutil.rmtree(extracted)
            else:
                os.unlink(extracted)
        if os.path.isdir(extracted_backup):
            shutil.copytree(extracted_backup, extracted)
DYNAMIC_EOF

verify_all() {
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
    test -f /home/user/project/extractor.cpp || return 1
    g++ -std=c++17 -O2 -I/home/user/project /home/user/project/extractor.cpp -o /tmp/extractor_under_test || return 1
    python3 /tmp/test_extractor_dynamic.py || return 1
}

if verify_all; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
