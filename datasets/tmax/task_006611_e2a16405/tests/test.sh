#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import tarfile
import hashlib
import pytest

BASE_DIR = "/home/user/artifact_dump"
MANIFEST_FILE = "/home/user/manifest.json"
ARCHIVE_FILE = "/home/user/clean_artifacts.tar.gz"

# Derive expectations from the immutable fixture definition rather than from
# agent-writable repository or log files.
def get_expected_artifacts():
    fixtures = [
        ("a.bin", "VER:1.0.0", b"random_data_A_12345"),
        (os.path.join("dir1", "b.bin"), "VER:2.1.0", b"random_data_B_67890"),
        (os.path.join("dir3", "d.bin"), "VER:3.0.0", b"random_data_D_99999"),
    ]
    expected = {}
    for rel_path, version, payload in fixtures:
        content = version.ljust(16, '-').encode('ascii') + payload
        file_hash = hashlib.sha256(content).hexdigest()
        expected[file_hash] = {
            "version": version,
            "path": rel_path,
        }
    return expected

def test_manifest_exists_and_correct():
    assert os.path.isfile(MANIFEST_FILE), f"Manifest file missing: {MANIFEST_FILE}"

    with open(MANIFEST_FILE, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Manifest is not valid JSON")

    expected = get_expected_artifacts()

    assert set(manifest.keys()) == set(expected.keys()), f"Manifest keys (hashes) do not match expected valid artifacts. Expected: {list(expected.keys())}, Got: {list(manifest.keys())}"

    for h, data in expected.items():
        assert manifest[h]["version"] == data["version"], f"Version mismatch for hash {h}. Expected {data['version']}, got {manifest[h]['version']}"
        manifest_path = manifest[h]["path"]
        abs_manifest_path = os.path.join(BASE_DIR, manifest_path)
        assert os.path.exists(abs_manifest_path), f"Path in manifest does not exist: {manifest_path}"
        assert abs_manifest_path.endswith(data["path"].split('/')[-1]), f"Path in manifest does not seem to point to the correct file: {manifest_path}"

def test_archive_exists_and_correct():
    assert os.path.isfile(ARCHIVE_FILE), f"Archive file missing: {ARCHIVE_FILE}"
    assert tarfile.is_tarfile(ARCHIVE_FILE), "Archive is not a valid tar file"

    expected = get_expected_artifacts()
    expected_filenames = {f"{h}.bin" for h in expected.keys()}

    with tarfile.open(ARCHIVE_FILE, "r:gz") as tar:
        members = tar.getmembers()

        for member in members:
            assert member.isfile(), f"Archive contains non-file member: {member.name}"
            assert "/" not in member.name and "\\" not in member.name, f"Archive contains nested file (not at root): {member.name}"

        actual_filenames = {member.name for member in members}
        assert actual_filenames == expected_filenames, f"Archive contents mismatch. Expected {expected_filenames}, got {actual_filenames}"

        for h in expected.keys():
            filename = f"{h}.bin"
            f = tar.extractfile(filename)
            assert f is not None, f"Could not extract {filename} from archive"
            content = f.read()
            actual_hash = hashlib.sha256(content).hexdigest()
            assert actual_hash == h, f"Hash mismatch for file {filename} in archive. File contents do not match the expected hash."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
