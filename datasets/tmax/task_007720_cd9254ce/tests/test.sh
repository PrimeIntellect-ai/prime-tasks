#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import hashlib
import struct
import zlib
import pytest

DATASET_DIR = '/home/user/dataset'
MANIFEST_PATH = '/home/user/manifest.json'
ARCHIVE_PATH = '/home/user/archive.bin'

def get_expected_files():
    expected_files = {}
    for root, dirs, files in os.walk(DATASET_DIR, followlinks=False):
        for f in files:
            full_path = os.path.join(root, f)
            if not os.path.islink(full_path) and os.path.isfile(full_path):
                if f.endswith('.dat') and os.path.getsize(full_path) > 51200:
                    rel_path = os.path.relpath(full_path, DATASET_DIR)
                    with open(full_path, 'rb') as fp:
                        expected_files[rel_path] = hashlib.sha256(fp.read()).hexdigest()
    return expected_files

def test_manifest_exists_and_correct():
    assert os.path.exists(MANIFEST_PATH), f"{MANIFEST_PATH} does not exist."
    with open(MANIFEST_PATH, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{MANIFEST_PATH} is not valid JSON.")

    expected_files = get_expected_files()
    assert set(manifest.keys()) == set(expected_files.keys()), "Manifest keys do not match the expected valid files."

    for rel_path, expected_hash in expected_files.items():
        assert manifest[rel_path] == expected_hash, f"Manifest hash for {rel_path} is incorrect."

def test_archive_exists_and_correct():
    assert os.path.exists(ARCHIVE_PATH), f"{ARCHIVE_PATH} does not exist."
    expected_files = get_expected_files()
    found_files = set()

    with open(ARCHIVE_PATH, 'rb') as f:
        while True:
            path_len_data = f.read(2)
            if not path_len_data:
                break

            assert len(path_len_data) == 2, "Unexpected EOF while reading path length."
            path_len = struct.unpack('<H', path_len_data)[0]

            parsed_rel_path = f.read(path_len).decode('utf-8')
            assert parsed_rel_path in expected_files, f"Unexpected file in archive: {parsed_rel_path}"

            orig_size_data = f.read(8)
            assert len(orig_size_data) == 8, "Unexpected EOF while reading original size."
            orig_size = struct.unpack('<Q', orig_size_data)[0]

            decomp = zlib.decompressobj()
            uncompressed_data = b""

            while not decomp.eof:
                chunk = f.read(1)
                if not chunk:
                    break
                uncompressed_data += decomp.decompress(chunk)

            assert decomp.eof, f"Incomplete compressed stream for {parsed_rel_path}"
            assert len(uncompressed_data) == orig_size, f"Uncompressed size mismatch for {parsed_rel_path}"

            real_hash = hashlib.sha256(uncompressed_data).hexdigest()
            assert real_hash == expected_files[parsed_rel_path], f"Extracted data checksum mismatch for {parsed_rel_path}"

            found_files.add(parsed_rel_path)

    assert found_files == set(expected_files.keys()), "Archive did not contain all expected files."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
