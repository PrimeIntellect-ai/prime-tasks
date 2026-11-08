#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import tarfile
import hashlib
import tempfile
import pytest

MANIFEST_PATH = "/home/user/dataset_manifest.json"
TARBALL_PATH = "/home/user/clean_datasets.tar.gz"

EXPECTED_FILES = {
    "exp1/results.csv": b"id,val\n1,10\n2,20\n",
    "exp1/config.json": b'{"env": "test"}',
    "exp2/data.csv": b"a,b,c\nx,y,z\n",
    "summary.json": b'{"total": 2}'
}

UNEXPECTED_FILES = [
    "exp1/run.log",
    "exp2/temp.tmp",
    "notes.txt"
]

def get_sha256(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()

def test_manifest_exists_and_correct():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing at {MANIFEST_PATH}"

    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Manifest file {MANIFEST_PATH} is not valid JSON.")

    assert isinstance(manifest, dict), "Manifest should be a JSON dictionary."

    expected_manifest = {
        path: get_sha256(content) for path, content in EXPECTED_FILES.items()
    }

    assert manifest == expected_manifest, f"Manifest contents do not match expected.\nExpected: {expected_manifest}\nGot: {manifest}"

def test_tarball_exists_and_contents():
    assert os.path.isfile(TARBALL_PATH), f"Tarball missing at {TARBALL_PATH}"

    with tempfile.TemporaryDirectory() as tmpdir:
        try:
            with tarfile.open(TARBALL_PATH, "r:gz") as tar:
                tar.extractall(path=tmpdir)
        except tarfile.TarError as e:
            pytest.fail(f"Failed to open or extract tarball: {e}")

        # Check manifest in tarball
        extracted_manifest_path = os.path.join(tmpdir, "dataset_manifest.json")
        assert os.path.isfile(extracted_manifest_path), "dataset_manifest.json is missing from the root of the tarball."

        with open(extracted_manifest_path, "r", encoding="utf-8") as f:
            extracted_manifest = json.load(f)

        expected_manifest = {
            path: get_sha256(content) for path, content in EXPECTED_FILES.items()
        }
        assert extracted_manifest == expected_manifest, "Manifest inside tarball does not match expected."

        # Check expected files in tarball
        for rel_path, expected_content in EXPECTED_FILES.items():
            extracted_file_path = os.path.join(tmpdir, rel_path)
            assert os.path.isfile(extracted_file_path), f"Expected dataset file {rel_path} is missing from the tarball."

            with open(extracted_file_path, "rb") as f:
                content = f.read()
            assert content == expected_content, f"Content of {rel_path} in tarball does not match expected."
            assert get_sha256(content) == expected_manifest[rel_path], f"Hash of {rel_path} in tarball does not match manifest."

        # Check unexpected files are NOT in tarball
        for rel_path in UNEXPECTED_FILES:
            extracted_file_path = os.path.join(tmpdir, rel_path)
            assert not os.path.exists(extracted_file_path), f"Junk file {rel_path} should not be included in the tarball."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
