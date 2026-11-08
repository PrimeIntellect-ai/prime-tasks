#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import hashlib
import struct
import pytest

STAGING_DIR = "/home/user/staging"
REPO_DIR = "/home/user/repo"
ORACLE_DIR = "/tests"
MANIFEST_PATH = os.path.join(REPO_DIR, "manifest.json")
CHUNK_SIZE = 102400

def get_original_artifact_info(basename):
    bin_path = os.path.join(STAGING_DIR, f"{basename}.bin")
    assert os.path.isfile(bin_path), f"Original staging file {bin_path} is missing."

    with open(bin_path, "rb") as f:
        header = f.read(16)
        payload = f.read()

    magic = header[0:4].decode('ascii')
    version = struct.unpack("<I", header[4:8])[0]
    payload_sha256 = hashlib.sha256(payload).hexdigest()

    return {
        "magic": magic,
        "version": version,
        "payload_sha256": payload_sha256,
        "payload": payload
    }

@pytest.fixture(scope="module")
def manifest():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file not found at {MANIFEST_PATH}"
    try:
        with open(MANIFEST_PATH, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Manifest file {MANIFEST_PATH} is not valid JSON.")
    return data

@pytest.mark.parametrize("artifact_name", ["core_sys", "net_utils"])
def test_staging_artifact_unchanged(artifact_name):
    staging_path = os.path.join(STAGING_DIR, f"{artifact_name}.bin")
    oracle_path = os.path.join(ORACLE_DIR, f"{artifact_name}.bin")
    assert os.path.isfile(staging_path), f"Original staging file {staging_path} is missing."
    assert os.path.isfile(oracle_path), f"Pristine verifier copy not found at {oracle_path}."
    with open(staging_path, "rb") as f:
        staging_data = f.read()
    with open(oracle_path, "rb") as f:
        oracle_data = f.read()
    assert staging_data == oracle_data, \
        f"Staging artifact {artifact_name}.bin was modified after setup."

@pytest.mark.parametrize("artifact_name", ["core_sys", "net_utils"])
def test_manifest_entries(manifest, artifact_name):
    assert artifact_name in manifest, f"Artifact '{artifact_name}' missing from manifest."

    entry = manifest[artifact_name]
    orig_info = get_original_artifact_info(artifact_name)

    assert entry.get("magic") == orig_info["magic"], \
        f"Expected magic '{orig_info['magic']}' for {artifact_name}, got '{entry.get('magic')}'"

    assert entry.get("version") == orig_info["version"], \
        f"Expected version {orig_info['version']} for {artifact_name}, got {entry.get('version')}"

    assert entry.get("payload_sha256") == orig_info["payload_sha256"], \
        f"Expected payload_sha256 {orig_info['payload_sha256']} for {artifact_name}, got {entry.get('payload_sha256')}"

    assert "chunks" in entry and isinstance(entry["chunks"], list), \
        f"Missing or invalid 'chunks' list for {artifact_name} in manifest."

@pytest.mark.parametrize("artifact_name", ["core_sys", "net_utils"])
def test_chunk_files_and_reassembly(manifest, artifact_name):
    orig_info = get_original_artifact_info(artifact_name)
    payload = orig_info["payload"]
    expected_num_chunks = (len(payload) + CHUNK_SIZE - 1) // CHUNK_SIZE

    entry = manifest.get(artifact_name, {})
    chunks_list = entry.get("chunks", [])

    assert len(chunks_list) == expected_num_chunks, \
        f"Expected {expected_num_chunks} chunks for {artifact_name}, but manifest lists {len(chunks_list)}."

    artifact_dir = os.path.join(REPO_DIR, artifact_name)
    assert os.path.isdir(artifact_dir), f"Directory for artifact chunks not found at {artifact_dir}"

    reassembled_payload = bytearray()

    for i, chunk_name in enumerate(chunks_list):
        expected_chunk_name = f"chunk_{i:02d}"
        assert chunk_name == expected_chunk_name, \
            f"Expected chunk name '{expected_chunk_name}', got '{chunk_name}'."

        chunk_path = os.path.join(artifact_dir, chunk_name)
        assert os.path.isfile(chunk_path), f"Chunk file missing: {chunk_path}"

        with open(chunk_path, "rb") as f:
            chunk_data = f.read()

        if i < expected_num_chunks - 1:
            assert len(chunk_data) == CHUNK_SIZE, \
                f"Expected {chunk_path} to be exactly {CHUNK_SIZE} bytes, got {len(chunk_data)} bytes."
        else:
            expected_remainder = len(payload) % CHUNK_SIZE or CHUNK_SIZE
            assert len(chunk_data) == expected_remainder, \
                f"Expected final chunk {chunk_path} to be {expected_remainder} bytes, got {len(chunk_data)} bytes."

        reassembled_payload.extend(chunk_data)

    assert reassembled_payload == payload, \
        f"Reassembled payload for {artifact_name} does not match the original payload data."

def test_no_extra_keys_in_manifest(manifest):
    expected_keys = {"core_sys", "net_utils"}
    actual_keys = set(manifest.keys())
    assert actual_keys == expected_keys, \
        f"Manifest contains unexpected keys. Expected {expected_keys}, got {actual_keys}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
