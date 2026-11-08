#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import hashlib
import pytest

CURATED_DIR = "/home/user/curated_dataset"
MANIFEST_PATH = "/home/user/curated_dataset/manifest.json"

EXPECTED_CSV = {
    "sensorA.csv": "/home/user/raw_data/session1/sensorA.csv",
    "sensorB.csv": "/home/user/raw_data/session2/subset/sensorB.csv",
    "sensorC.csv": "/home/user/raw_data/session3/logs/sensorC.csv"
}

def test_curated_directory_exists():
    assert os.path.isdir(CURATED_DIR), f"Directory missing: {CURATED_DIR}"

def test_symlinks_exist_and_correct():
    for filename, original_path in EXPECTED_CSV.items():
        symlink_path = os.path.join(CURATED_DIR, filename)
        assert os.path.islink(symlink_path), f"Expected a symbolic link at {symlink_path}"
        target = os.readlink(symlink_path)
        assert target == original_path, f"Symlink {symlink_path} points to {target}, expected {original_path}"

def test_manifest_exists_and_valid():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing: {MANIFEST_PATH}"

    with open(MANIFEST_PATH, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("manifest.json is not a valid JSON file")

    assert isinstance(manifest, dict), "Manifest should be a JSON dictionary"

    for filename, original_path in EXPECTED_CSV.items():
        assert filename in manifest, f"Manifest is missing entry for {filename}"
        entry = manifest[filename]

        assert "symlink_path" in entry, f"Missing 'symlink_path' for {filename}"
        expected_symlink = os.path.join(CURATED_DIR, filename)
        assert entry["symlink_path"] == expected_symlink, f"Incorrect symlink_path for {filename}"

        assert "original_path" in entry, f"Missing 'original_path' for {filename}"
        assert entry["original_path"] == original_path, f"Incorrect original_path for {filename}"

        assert "sha256" in entry, f"Missing 'sha256' for {filename}"

        # Compute sha256 dynamically to verify
        with open(original_path, "rb") as orig_f:
            expected_sha256 = hashlib.sha256(orig_f.read()).hexdigest()

        assert entry["sha256"] == expected_sha256, f"Incorrect sha256 for {filename}"

    # Check for extra keys
    extra_keys = set(manifest.keys()) - set(EXPECTED_CSV.keys())
    assert not extra_keys, f"Manifest contains unexpected entries: {extra_keys}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
