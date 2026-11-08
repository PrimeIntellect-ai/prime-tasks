#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile
import hashlib
import subprocess
import gzip
import pytest

DATA_VOLUME = "/home/user/data_volume"
MANIFEST_PATH = "/home/user/manifest.txt"
TAR_PATH = "/home/user/cold_storage.tar"
VERIFY_SCRIPT_PATH = "/home/user/verify.py"

EXPECTED_FILES = [
    "dumps/dataC.bin",
    "logs/fileA.txt",
    "logs/fileB.txt"
]

UNEXPECTED_FILES = [
    "dumps/dataE.bin",
    "logs/fileD.txt"
]

def get_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(8192):
            sha256.update(chunk)
    return sha256.hexdigest()

def test_manifest_exists_and_correct():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing at {MANIFEST_PATH}"

    with open(MANIFEST_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(EXPECTED_FILES), f"Manifest should have exactly {len(EXPECTED_FILES)} entries, got {len(lines)}"

    # Check sorted order
    paths_in_manifest = [line.split()[0] for line in lines]
    assert paths_in_manifest == sorted(paths_in_manifest), "Manifest lines must be sorted alphabetically by relative path"

    manifest_dict = {}
    for line in lines:
        parts = line.split()
        assert len(parts) == 2, f"Invalid manifest line format: {line}"
        manifest_dict[parts[0]] = parts[1]

    for expected_file in EXPECTED_FILES:
        assert expected_file in manifest_dict, f"Expected file {expected_file} missing from manifest"
        original_path = os.path.join(DATA_VOLUME, expected_file)
        expected_hash = get_sha256(original_path)
        assert manifest_dict[expected_file] == expected_hash, f"Hash mismatch in manifest for {expected_file}"

    for unexpected_file in UNEXPECTED_FILES:
        assert unexpected_file not in manifest_dict, f"Unexpected file {unexpected_file} found in manifest"

def test_tar_archive_contents():
    assert os.path.isfile(TAR_PATH), f"Tar archive missing at {TAR_PATH}"

    expected_tar_members = {
        "dumps/dataC.bin.gz",
        "logs/fileA.txt.rle",
        "logs/fileB.txt.rle"
    }

    with tarfile.open(TAR_PATH, 'r') as tar:
        members = tar.getnames()
        assert set(members) == expected_tar_members, f"Tar archive contents mismatch. Expected {expected_tar_members}, got {set(members)}"

def test_verify_script_execution():
    assert os.path.isfile(VERIFY_SCRIPT_PATH), f"Verify script missing at {VERIFY_SCRIPT_PATH}"

    result = subprocess.run(
        ["python3", VERIFY_SCRIPT_PATH],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"Verify script exited with non-zero code: {result.returncode}\nStderr: {result.stderr}"
    assert result.stdout.strip() == "INTEGRITY_PASSED", f"Verify script output incorrect. Expected 'INTEGRITY_PASSED', got '{result.stdout.strip()}'"

def test_rle_compression_validity():
    with tarfile.open(TAR_PATH, 'r') as tar:
        for member in tar.getmembers():
            if member.name.endswith('.rle'):
                f = tar.extractfile(member)
                compressed_data = f.read()

                # Decompress RLE
                decompressed = bytearray()
                assert len(compressed_data) % 2 == 0, f"RLE compressed data for {member.name} has odd length"

                for i in range(0, len(compressed_data), 2):
                    count = compressed_data[i]
                    byte_val = compressed_data[i+1]
                    assert 1 <= count <= 255, f"Invalid RLE count {count} in {member.name}"
                    decompressed.extend(bytes([byte_val]) * count)

                original_path = os.path.join(DATA_VOLUME, member.name[:-4])
                with open(original_path, 'rb') as orig:
                    original_data = orig.read()

                assert decompressed == original_data, f"Decompressed RLE data does not match original for {member.name}"

def test_gzip_compression_validity():
    with tarfile.open(TAR_PATH, 'r') as tar:
        for member in tar.getmembers():
            if member.name.endswith('.gz'):
                f = tar.extractfile(member)
                compressed_data = f.read()

                decompressed = gzip.decompress(compressed_data)

                original_path = os.path.join(DATA_VOLUME, member.name[:-3])
                with open(original_path, 'rb') as orig:
                    original_data = orig.read()

                assert decompressed == original_data, f"Decompressed gzip data does not match original for {member.name}"

def test_verify_script_actually_verifies_dynamic_artifacts():
    import io
    import secrets

    with open(TAR_PATH, 'rb') as f:
        original_tar = f.read()
    with open(MANIFEST_PATH, 'rb') as f:
        original_manifest = f.read()

    nonce = secrets.token_hex(8)
    text_path = f"probe_{nonce}/sample.txt"
    binary_path = f"probe_{nonce}/sample.bin"
    text_data = b'A' * 260 + os.urandom(31) + b'Z' * 511
    binary_data = os.urandom(4096)

    def rle_encode(data):
        encoded = bytearray()
        i = 0
        while i < len(data):
            run = 1
            while i + run < len(data) and data[i + run] == data[i] and run < 255:
                run += 1
            encoded.extend((run, data[i]))
            i += run
        return bytes(encoded)

    def write_archive(stored_text, stored_binary):
        members = {
            text_path + '.rle': rle_encode(stored_text),
            binary_path + '.gz': gzip.compress(stored_binary),
        }
        with tarfile.open(TAR_PATH, 'w') as tar:
            for name, payload in members.items():
                info = tarfile.TarInfo(name)
                info.size = len(payload)
                info.mode = 0o644
                tar.addfile(info, io.BytesIO(payload))

    def write_manifest(text_hash, binary_hash):
        entries = [
            (text_path, text_hash),
            (binary_path, binary_hash),
        ]
        entries.sort()
        with open(MANIFEST_PATH, 'w') as f:
            for path, digest in entries:
                f.write(f"{path} {digest}\n")

    def run_verifier():
        return subprocess.run(
            ["python3", VERIFY_SCRIPT_PATH],
            capture_output=True,
            text=True
        )

    text_hash = hashlib.sha256(text_data).hexdigest()
    binary_hash = hashlib.sha256(binary_data).hexdigest()

    try:
        # A fresh, unpredictable archive and matching manifest must pass.
        write_archive(text_data, binary_data)
        write_manifest(text_hash, binary_hash)
        result = run_verifier()
        assert result.returncode == 0, f"Verifier rejected valid dynamic artifacts: {result.stderr or result.stdout}"
        assert result.stdout.strip() == "INTEGRITY_PASSED", "Verifier output is incorrect for valid dynamic artifacts"

        # A manifest discrepancy must be detected.
        write_manifest('0' * 64, binary_hash)
        result = run_verifier()
        assert result.returncode != 0, "Verifier accepted a manifest containing an incorrect hash"

        # Restore the valid manifest, then independently alter each compressed payload.
        write_manifest(text_hash, binary_hash)
        write_archive(text_data + b'changed', binary_data)
        result = run_verifier()
        assert result.returncode != 0, "Verifier accepted altered RLE-compressed content"

        write_archive(text_data, binary_data + b'changed')
        result = run_verifier()
        assert result.returncode != 0, "Verifier accepted altered gzip-compressed content"
    finally:
        with open(TAR_PATH, 'wb') as f:
            f.write(original_tar)
        with open(MANIFEST_PATH, 'wb') as f:
            f.write(original_manifest)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
