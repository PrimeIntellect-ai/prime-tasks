#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import hashlib
import pytest

INCOMING_DIR = "/home/user/incoming"
METADATA_FILE = "/home/user/incoming/metadata.csv"
POOL_DIR = "/home/user/artifact_pool"
CURATED_DIR = "/home/user/curated_repo"
MANIFEST_FILE = "/home/user/curated_repo/manifest.txt"

INITIAL_METADATA = (
    b"projA/mac/release.zip,macos,1.0.0\n"
    b"projB/win/binary.exe,windows,2.1.0\n"
    b"shared/linux/app.tar.gz,linux,3.0.1\n"
)

INITIAL_ARTIFACTS = [
    ("projA/mac/release.zip", "macos", "1.0.0", b"dummy mac file"),
    ("projB/win/binary.exe", "windows", "2.1.0", b"dummy win file"),
    ("shared/linux/app.tar.gz", "linux", "3.0.1", b"dummy linux file"),
]

def get_expected_state():
    if not os.path.isfile(METADATA_FILE):
        pytest.fail(f"Metadata file missing: {METADATA_FILE}")

    with open(METADATA_FILE, "rb") as f:
        actual_metadata = f.read()
    if actual_metadata != INITIAL_METADATA:
        pytest.fail(f"Metadata file was modified: {METADATA_FILE}")

    expected_state = []
    for rel_path, os_target, version, content in INITIAL_ARTIFACTS:
        abs_path = os.path.join(INCOMING_DIR, rel_path)

        if not os.path.isfile(abs_path):
            pytest.fail(f"Original file missing: {abs_path}")

        sha256_hash = hashlib.sha256(content).hexdigest()

        basename = os.path.basename(rel_path)
        if "." in basename:
            ext = basename[basename.find("."):]
        else:
            ext = ""

        pool_file = os.path.join(POOL_DIR, f"{sha256_hash}{ext}")
        symlink_file = os.path.join(CURATED_DIR, os_target, version, f"artifact{ext}")
        manifest_line = f"{symlink_file}|{pool_file}|{sha256_hash}"

        expected_state.append({
            "original_path": abs_path,
            "original_content": content,
            "sha256": sha256_hash,
            "pool_file": pool_file,
            "symlink_file": symlink_file,
            "manifest_line": manifest_line,
        })

    return expected_state

@pytest.fixture(scope="module")
def expected_data():
    return get_expected_state()

def test_original_files_unmodified(expected_data):
    for item in expected_data:
        path = item["original_path"]
        assert os.path.isfile(path), f"Original file was deleted or moved: {path}"
        with open(path, "rb") as f:
            assert f.read() == item["original_content"], f"Original file was modified: {path}"

def test_artifact_pool_files(expected_data):
    assert os.path.isdir(POOL_DIR), f"Artifact pool directory missing: {POOL_DIR}"
    for item in expected_data:
        pool_file = item["pool_file"]
        assert os.path.isfile(pool_file), f"Missing file in artifact pool: {pool_file}"
        with open(pool_file, "rb") as f:
            assert f.read() == item["original_content"], f"Content mismatch in pool file: {pool_file}"

def test_curated_repo_symlinks(expected_data):
    assert os.path.isdir(CURATED_DIR), f"Curated repo directory missing: {CURATED_DIR}"
    for item in expected_data:
        symlink_file = item["symlink_file"]
        pool_file = item["pool_file"]

        assert os.path.islink(symlink_file), f"Expected a symbolic link at: {symlink_file}"
        target = os.readlink(symlink_file)
        assert target == pool_file, f"Symlink {symlink_file} points to {target}, expected absolute path {pool_file}"

def test_manifest_file(expected_data):
    assert os.path.isfile(MANIFEST_FILE), f"Manifest file missing: {MANIFEST_FILE}"

    expected_lines = sorted([item["manifest_line"] for item in expected_data])

    with open(MANIFEST_FILE, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, "Manifest file contents or sorting do not match expected."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
