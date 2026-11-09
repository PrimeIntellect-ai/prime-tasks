#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import pytest

RAW_CHUNK_FIXTURE = {
    "scrambled_xyz_0.dat": b"chunk1_data_aaaaa",
    "scrambled_xyz_1.dat": b"chunk2_data_bbbbb",
    "scrambled_xyz_2.dat": b"chunk3_data_ccccc",
    "scrambled_xyz_3.dat": b"db_part1_11111",
    "scrambled_xyz_4.dat": b"db_part2_22222",
    "scrambled_xyz_5.dat": b"zip_partA",
    "scrambled_xyz_6.dat": b"zip_partB",
    "scrambled_xyz_7.dat": b"zip_partC",
}

EXPECTED_MANIFEST = {
    "artifacts": [
        {
            "canonical_name": "app_release_linux_amd64.tar.gz",
            "chunks": [
                "scrambled_xyz_0.dat",
                "scrambled_xyz_1.dat",
                "scrambled_xyz_2.dat",
            ],
            "expected_sha256": hashlib.sha256(
                b"chunk1_data_aaaaa" + b"chunk2_data_bbbbb" + b"chunk3_data_ccccc"
            ).hexdigest(),
        },
        {
            "canonical_name": "database_schema.sqlite",
            "chunks": ["scrambled_xyz_3.dat", "scrambled_xyz_4.dat"],
            "expected_sha256": hashlib.sha256(
                b"db_part1_11111" + b"db_part2_22222"
            ).hexdigest(),
        },
        {
            "canonical_name": "legacy_drivers.zip",
            "chunks": [
                "scrambled_xyz_5.dat",
                "scrambled_xyz_6.dat",
                "scrambled_xyz_7.dat",
            ],
            "expected_sha256": hashlib.sha256(
                b"zip_partA" + b"zip_partB" + b"zip_partC"
            ).hexdigest(),
        },
    ]
}

def get_file_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def test_original_input_fixture_is_intact():
    manifest_path = "/home/user/manifest.json"
    raw_chunks_dir = "/home/user/raw_chunks"

    assert os.path.isfile(manifest_path), f"Manifest file missing at {manifest_path}"
    with open(manifest_path, "r") as f:
        manifest = json.load(f)
    assert manifest == EXPECTED_MANIFEST, "The manifest does not match the original task fixture."

    for chunk_name, expected_data in RAW_CHUNK_FIXTURE.items():
        chunk_path = os.path.join(raw_chunks_dir, chunk_name)
        assert os.path.isfile(chunk_path), f"Original chunk missing at {chunk_path}"
        with open(chunk_path, "rb") as cf:
            assert cf.read() == expected_data, f"Original chunk was modified: {chunk_name}"

def test_curated_artifacts_directory_exists():
    curated_dir = "/home/user/curated_artifacts"
    assert os.path.isdir(curated_dir), f"Directory {curated_dir} does not exist."

def test_reconstructed_artifacts():
    manifest_path = "/home/user/manifest.json"
    raw_chunks_dir = "/home/user/raw_chunks"
    curated_dir = "/home/user/curated_artifacts"
    log_file = os.path.join(curated_dir, "integrity_failures.log")

    assert os.path.isfile(manifest_path), f"Manifest file missing at {manifest_path}"

    with open(manifest_path, 'r') as f:
        manifest = json.load(f)

    assert manifest == EXPECTED_MANIFEST, "The manifest does not match the original task fixture."

    expected_failures = []

    for artifact in manifest.get("artifacts", []):
        canonical_name = artifact["canonical_name"]
        expected_sha256 = artifact["expected_sha256"]
        chunks = artifact["chunks"]

        # Reconstruct from raw chunks to see if it's corrupt
        merged_data = b""
        for chunk_name in chunks:
            chunk_path = os.path.join(raw_chunks_dir, chunk_name)
            with open(chunk_path, "rb") as cf:
                merged_data += cf.read()

        actual_sha256 = hashlib.sha256(merged_data).hexdigest()

        artifact_path = os.path.join(curated_dir, canonical_name)

        if actual_sha256 == expected_sha256:
            # Should be successfully reconstructed
            assert os.path.isfile(artifact_path), f"Valid artifact {canonical_name} was not saved to {curated_dir}."
            saved_sha256 = get_file_sha256(artifact_path)
            assert saved_sha256 == expected_sha256, f"Checksum mismatch for {canonical_name}. Expected {expected_sha256}, got {saved_sha256}."
        else:
            # Should be marked as corrupt
            assert not os.path.isfile(artifact_path), f"Corrupt artifact {canonical_name} should not have been saved to {curated_dir}."
            expected_failures.append(canonical_name)

    # Check integrity_failures.log
    if expected_failures:
        assert os.path.isfile(log_file), f"Log file {log_file} does not exist but there were integrity failures."
        with open(log_file, "r") as lf:
            logged_failures = [line.strip() for line in lf.readlines() if line.strip()]

        for failure in expected_failures:
            assert failure in logged_failures, f"Corrupt artifact {failure} was not logged in {log_file}."

        assert len(logged_failures) == len(expected_failures), f"Log file contains unexpected entries. Expected {len(expected_failures)}, found {len(logged_failures)}."
    else:
        if os.path.exists(log_file):
            with open(log_file, "r") as lf:
                content = lf.read().strip()
            assert not content, f"Log file {log_file} should be empty, but contains data."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
