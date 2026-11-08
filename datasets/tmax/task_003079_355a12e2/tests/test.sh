#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import zipfile
import pytest

def calculate_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def get_incoming_artifact(filename):
    matches = []
    incoming_dir = "/home/user/incoming"
    for archive_name in sorted(os.listdir(incoming_dir)):
        if not archive_name.endswith(".zip"):
            continue
        archive_path = os.path.join(incoming_dir, archive_name)
        with zipfile.ZipFile(archive_path, "r") as archive:
            for member in archive.infolist():
                if not member.is_dir() and os.path.basename(member.filename) == filename:
                    matches.append(archive.read(member))
    assert len(matches) == 1, f"Expected exactly one incoming archive member named {filename}, found {len(matches)}."
    return matches[0]

def test_final_state():
    repo_dir = "/home/user/repo"
    manifest_path = "/home/user/repo/manifest.json"

    # 1. Verify manifest exists
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} does not exist."

    # 2. Parse manifest
    with open(manifest_path, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Manifest file {manifest_path} is not valid JSON.")

    assert "artifacts" in manifest, "Manifest missing 'artifacts' key."
    artifacts = manifest["artifacts"]
    assert isinstance(artifacts, list), "'artifacts' should be a list."
    assert len(artifacts) == 2, f"Expected exactly 2 artifacts in manifest, found {len(artifacts)}."

    # 3. Expected files
    expected_files = {
        "toolA-1.0-x86_64.tar.gz": {
            "architecture": "x86_64",
            "path": "x86_64/toolA-1.0-x86_64.tar.gz"
        },
        "toolB-2.0-arm64.tar.gz": {
            "architecture": "arm64",
            "path": "arm64/toolB-2.0-arm64.tar.gz"
        }
    }

    # 4. Verify each artifact in the manifest and on disk
    found_filenames = set()
    for artifact in artifacts:
        filename = artifact.get("filename")
        assert filename in expected_files, f"Unexpected filename in manifest: {filename}"
        found_filenames.add(filename)

        expected = expected_files[filename]
        assert artifact.get("architecture") == expected["architecture"], f"Incorrect architecture for {filename}"
        assert artifact.get("path") == expected["path"], f"Incorrect path for {filename}"

        # Check that the file actually exists on disk
        full_path = os.path.join(repo_dir, expected["path"])
        assert os.path.isfile(full_path), f"Expected artifact file {full_path} does not exist."

        # Check the checksum
        actual_checksum = calculate_sha256(full_path)
        manifest_checksum = artifact.get("checksum")
        assert manifest_checksum == actual_checksum, f"Checksum mismatch for {filename}. Expected {actual_checksum}, got {manifest_checksum}"

        # Check that the curated artifact is byte-for-byte identical to the
        # corresponding member of the incoming archive.
        incoming_bytes = get_incoming_artifact(filename)
        with open(full_path, "rb") as curated_file:
            curated_bytes = curated_file.read()
        assert curated_bytes == incoming_bytes, f"Curated artifact {filename} does not match the incoming archive member."

    assert len(found_filenames) == 2, "Manifest does not contain all expected artifacts."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
