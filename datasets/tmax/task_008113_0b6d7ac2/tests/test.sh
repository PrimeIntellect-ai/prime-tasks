#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import secrets
import subprocess
import tempfile
import pytest

RAW_DIR = "/home/user/artifacts/raw"
LATEST_DIR = "/home/user/artifacts/latest"
TOOL_DIR = "/home/user/rle_tool"
MANIFEST_PATH = os.path.join(TOOL_DIR, "Cargo.toml")
MAIN_PATH = os.path.join(TOOL_DIR, "src", "main.rs")

def decode_rle(blob_path):
    """Decodes the custom RLE format from the given blob file."""
    with open(blob_path, 'rb') as f:
        data = f.read()

    out = bytearray()
    for i in range(0, len(data), 2):
        if i + 1 >= len(data):
            break
        count = data[i]
        if count == 0:
            break
        value = data[i+1]
        out.extend(bytes([value]) * count)
    return bytes(out)

def decode_bytes(data):
    out = bytearray()
    for i in range(0, len(data), 2):
        if i + 1 >= len(data):
            break
        count = data[i]
        if count == 0:
            break
        out.extend(bytes([data[i + 1]]) * count)
    return bytes(out)

def get_blob_files(directory):
    blob_files = []
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith(".blob"):
                blob_files.append(os.path.join(root, file))
    return blob_files

def test_rust_tool_exists_and_executes():
    """Check that the requested Rust project exists and its utility really decodes RLE."""
    assert os.path.isdir(TOOL_DIR), f"Rust project directory missing: {TOOL_DIR}"
    assert os.path.isfile(MANIFEST_PATH), f"Cargo manifest missing: {MANIFEST_PATH}"
    assert os.path.isfile(MAIN_PATH), f"Rust program source missing: {MAIN_PATH}"

    random_pairs = bytearray()
    for _ in range(12):
        random_pairs.extend((secrets.randbelow(31) + 1, secrets.randbelow(256)))

    cases = [
        bytes(random_pairs),
        bytes(random_pairs) + bytes((0, secrets.randbelow(256), 9, 77)),
        bytes((0, secrets.randbelow(256), 4, 123)),
    ]

    with tempfile.TemporaryDirectory() as temp_dir:
        for index, encoded in enumerate(cases):
            input_path = os.path.join(temp_dir, f"case{index}.blob")
            output_path = os.path.join(temp_dir, f"case{index}.bin")
            with open(input_path, "wb") as f:
                f.write(encoded)

            result = subprocess.run(
                ["cargo", "run", "--quiet", "--manifest-path", MANIFEST_PATH,
                 "--", input_path, output_path],
                cwd=TOOL_DIR,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=120,
                check=False,
            )
            assert result.returncode == 0, (
                f"Rust utility failed with exit code {result.returncode}. "
                f"stderr: {result.stderr.decode(errors='replace')}"
            )
            assert os.path.isfile(output_path), f"Rust utility did not create {output_path}"
            with open(output_path, "rb") as f:
                actual = f.read()
            assert actual == decode_bytes(encoded), (
                f"Rust utility decoded generated input incorrectly: expected "
                f"{decode_bytes(encoded)!r}, got {actual!r}"
            )

def test_latest_directory_exists():
    """Test that the latest directory was created."""
    assert os.path.exists(LATEST_DIR), f"Directory {LATEST_DIR} does not exist."
    assert os.path.isdir(LATEST_DIR), f"{LATEST_DIR} is not a directory."

def test_decompressed_files_and_symlinks():
    """Test that all .blob files are decompressed correctly and symlinked."""
    blob_files = get_blob_files(RAW_DIR)
    assert len(blob_files) > 0, f"No .blob files found in {RAW_DIR}."

    expected_symlinks = set()

    for blob_path in blob_files:
        # Decode the expected content
        expected_content = decode_rle(blob_path)

        # Check the .bin file
        bin_path = blob_path[:-5] + ".bin"
        assert os.path.exists(bin_path), f"Decompressed file missing: {bin_path}"
        assert os.path.isfile(bin_path), f"Expected file, found directory: {bin_path}"

        with open(bin_path, 'rb') as f:
            actual_content = f.read()

        assert actual_content == expected_content, f"Content mismatch in {bin_path}. Expected {expected_content}, got {actual_content}"

        # Calculate SHA256
        sha256_hash = hashlib.sha256(expected_content).hexdigest()
        symlink_name = f"{sha256_hash}.bin"
        symlink_path = os.path.join(LATEST_DIR, symlink_name)

        expected_symlinks.add(symlink_name)

        # Check the symlink
        assert os.path.exists(symlink_path), f"Symlink missing: {symlink_path}"
        assert os.path.islink(symlink_path), f"Expected symlink, but it is not a link: {symlink_path}"

        target_path = os.readlink(symlink_path)
        assert target_path == bin_path, f"Symlink {symlink_path} points to {target_path}, expected absolute path {bin_path}"

def test_no_extra_symlinks_in_latest():
    """Test that the latest directory contains exactly the expected symlinks and nothing else."""
    blob_files = get_blob_files(RAW_DIR)
    expected_symlinks = set()
    for blob_path in blob_files:
        expected_content = decode_rle(blob_path)
        sha256_hash = hashlib.sha256(expected_content).hexdigest()
        expected_symlinks.add(f"{sha256_hash}.bin")

    if os.path.exists(LATEST_DIR):
        actual_files = set(os.listdir(LATEST_DIR))
        extra_files = actual_files - expected_symlinks
        missing_files = expected_symlinks - actual_files

        assert not extra_files, f"Found unexpected files in {LATEST_DIR}: {extra_files}"
        assert not missing_files, f"Missing expected files in {LATEST_DIR}: {missing_files}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
