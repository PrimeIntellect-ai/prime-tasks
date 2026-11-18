#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import tarfile
import glob
import re
import pytest

CONFIGS_DIR = "/home/user/configs"
MANIFEST_PATH = "/home/user/configs/manifest.json"
TARBALL_PATH = "/home/user/configs_backup.tar.gz"
COLD_STORAGE_DIR = "/home/user/cold_storage"

EXPECTED_CONFIGS = {
    "web_01/1690000000.conf": "server {\n  listen 80;\n  server_name example.com;\n}\n",
    "db_master/1690000500.conf": "max_connections=500\nshared_buffers=2GB\n",
    "cache_node/1690001000.conf": "".join([f"bind 192.168.1.{i}\n" for i in range(50)])
}

def get_sha256(content: str) -> str:
    return hashlib.sha256(content.encode("utf-8")).hexdigest()

def test_extracted_configs():
    for rel_path, expected_content in EXPECTED_CONFIGS.items():
        full_path = os.path.join(CONFIGS_DIR, rel_path)
        assert os.path.isfile(full_path), f"Expected configuration file missing: {full_path}"
        with open(full_path, "r") as f:
            content = f.read()
        assert content == expected_content, f"Content mismatch in {full_path}"

def test_manifest_json():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing: {MANIFEST_PATH}"
    with open(MANIFEST_PATH, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Manifest is not valid JSON")

    for rel_path, expected_content in EXPECTED_CONFIGS.items():
        assert rel_path in manifest, f"Manifest missing entry for {rel_path}"
        expected_hash = get_sha256(expected_content)
        assert manifest[rel_path] == expected_hash, f"Hash mismatch in manifest for {rel_path}"

def test_tarball_exists_and_valid():
    assert os.path.isfile(TARBALL_PATH), f"Tarball missing: {TARBALL_PATH}"
    assert tarfile.is_tarfile(TARBALL_PATH), f"File is not a valid tarball: {TARBALL_PATH}"

    with tarfile.open(TARBALL_PATH, "r:gz") as tar:
        members = tar.getmembers()
        names = tar.getnames()

        # Preserve the original root and expected-member checks.
        assert any(name == "configs" or name.startswith("configs/") for name in names), "Tarball must have 'configs' as the root directory"
        for rel_path in EXPECTED_CONFIGS.keys():
            expected_tar_path = f"configs/{rel_path}"
            assert expected_tar_path in names, f"Tarball missing file: {expected_tar_path}"

        # Every member must be canonically rooted under configs/.
        for member in members:
            trimmed = member.name.rstrip("/")
            parts = trimmed.split("/") if trimmed else []
            assert parts and parts[0] == "configs", f"Archive member is outside configs/: {member.name}"
            assert all(part not in ("", ".", "..") for part in parts), f"Non-canonical archive member path: {member.name}"

        regular_members = [member for member in members if member.isfile()]
        regular_names = [member.name for member in regular_members]
        assert len(regular_names) == len(set(regular_names)), "Tarball contains duplicate file members"
        assert "configs/manifest.json" in regular_names, "Tarball missing file: configs/manifest.json"

        # The archive must contain every file in the actual configs tree, and no fabricated files.
        disk_files = {}
        for root, _, files in os.walk(CONFIGS_DIR):
            for filename in files:
                full_path = os.path.join(root, filename)
                assert os.path.isfile(full_path), f"Configs entry is not a regular file: {full_path}"
                rel_path = os.path.relpath(full_path, CONFIGS_DIR).replace(os.sep, "/")
                with open(full_path, "rb") as f:
                    disk_files[f"configs/{rel_path}"] = f.read()

        assert set(regular_names) == set(disk_files), "Tarball file set does not match the configs directory"
        for member in regular_members:
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archived file: {member.name}"
            assert extracted.read() == disk_files[member.name], f"Archived content mismatch: {member.name}"

        # Independently verify the archived configurations against their required contents.
        by_name = {member.name: member for member in regular_members}
        for rel_path, expected_content in EXPECTED_CONFIGS.items():
            archived = tar.extractfile(by_name[f"configs/{rel_path}"])
            assert archived.read() == expected_content.encode("utf-8"), f"Archived configuration content mismatch: {rel_path}"

def suffix_for_index(index):
    assert 0 <= index < 26 * 26, "Too many chunks for two-letter suffixes"
    return chr(ord("a") + index // 26) + chr(ord("a") + index % 26)

def test_chunks_and_reassembly():
    assert os.path.isdir(COLD_STORAGE_DIR), f"Cold storage directory missing: {COLD_STORAGE_DIR}"

    chunks = sorted(glob.glob(os.path.join(COLD_STORAGE_DIR, "backup.part_*")))
    assert len(chunks) > 0, "No backup chunks found in cold storage"

    for index, chunk in enumerate(chunks):
        basename = os.path.basename(chunk)
        assert re.fullmatch(r"backup\.part_[a-z]{2}", basename), f"Invalid chunk filename: {basename}"
        assert basename == f"backup.part_{suffix_for_index(index)}", f"Chunk suffix sequence is invalid at {basename}"
        assert os.path.isfile(chunk), f"Chunk is not a regular file: {chunk}"

    # Preserve the original full-chunk size check and constrain the final chunk too.
    for chunk in chunks[:-1]:
        assert os.path.getsize(chunk) == 1024, f"Chunk {chunk} is not exactly 1024 bytes"
    final_size = os.path.getsize(chunks[-1])
    assert 1 <= final_size <= 1024, f"Final chunk {chunks[-1]} must contain between 1 and 1024 bytes"

    tarball_size = os.path.getsize(TARBALL_PATH)
    expected_count = (tarball_size + 1023) // 1024
    assert len(chunks) == expected_count, "Chunk count does not match 1024-byte splitting"

    # Reassemble and compare with original tarball.
    reassembled_content = bytearray()
    for chunk in chunks:
        with open(chunk, "rb") as f:
            reassembled_content.extend(f.read())

    with open(TARBALL_PATH, "rb") as f:
        original_content = f.read()

    assert reassembled_content == original_content, "Reassembled chunks do not match the original tarball exactly"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
