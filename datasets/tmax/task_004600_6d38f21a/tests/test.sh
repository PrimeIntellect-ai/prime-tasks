#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import glob
import pytest

ARTIFACTS_DIR = "/home/user/project/artifacts"
ORGANIZED_DIR = "/home/user/project/organized"
CHUNKS_DIR = "/home/user/project/chunks"

def test_organized_directory_exists():
    assert os.path.exists(ORGANIZED_DIR), f"Directory {ORGANIZED_DIR} does not exist."
    assert os.path.isdir(ORGANIZED_DIR), f"{ORGANIZED_DIR} is not a directory."

def test_organized_directory_contents():
    expected_files = {
        "exe_blobA.bin",
        "obj_blobB.o",
        "exe_blobD.bin",
        "obj_blobE.o"
    }

    actual_files = set(os.listdir(ORGANIZED_DIR))

    assert actual_files == expected_files, (
        f"Expected files in {ORGANIZED_DIR} to be exactly {expected_files}, "
        f"but found {actual_files}."
    )

@pytest.mark.parametrize("organized_name, artifact_name", [
    ("exe_blobA.bin", "blobA"),
    ("obj_blobB.o", "blobB"),
    ("exe_blobD.bin", "blobD"),
    ("obj_blobE.o", "blobE"),
])
def test_organized_files_content(organized_name, artifact_name):
    org_path = os.path.join(ORGANIZED_DIR, organized_name)
    art_path = os.path.join(ARTIFACTS_DIR, artifact_name)

    assert os.path.exists(org_path), f"File {org_path} is missing."
    assert os.path.exists(art_path), f"Original file {art_path} is missing."

    with open(org_path, "rb") as f1, open(art_path, "rb") as f2:
        assert f1.read() == f2.read(), f"Content of {org_path} does not match {art_path}."

def test_chunks_directory_exists():
    assert os.path.exists(CHUNKS_DIR), f"Directory {CHUNKS_DIR} does not exist."
    assert os.path.isdir(CHUNKS_DIR), f"{CHUNKS_DIR} is not a directory."

def test_chunks_files_and_sizes():
    chunk_files = sorted(glob.glob(os.path.join(CHUNKS_DIR, "part_*")))
    assert len(chunk_files) > 0, f"No chunk files found in {CHUNKS_DIR} matching 'part_*'."

    for i, chunk_file in enumerate(chunk_files):
        size = os.path.getsize(chunk_file)
        if i < len(chunk_files) - 1:
            assert size == 1024, f"Chunk {chunk_file} size is {size}, expected exactly 1024 bytes."
        else:
            assert size <= 1024, f"Last chunk {chunk_file} size is {size}, expected <= 1024 bytes."

def test_reconstructed_executable():
    chunk_files = sorted(glob.glob(os.path.join(CHUNKS_DIR, "part_*")))
    assert len(chunk_files) > 0, f"No chunk files found in {CHUNKS_DIR} matching 'part_*'."

    reconstructed_data = b""
    for chunk_file in chunk_files:
        with open(chunk_file, "rb") as f:
            reconstructed_data += f.read()

    largest_exe_path = os.path.join(ORGANIZED_DIR, "exe_blobD.bin")
    assert os.path.exists(largest_exe_path), f"Largest executable {largest_exe_path} is missing."

    with open(largest_exe_path, "rb") as f:
        expected_data = f.read()

    assert reconstructed_data == expected_data, (
        "Concatenated chunks do not match the content of the largest executable (exe_blobD.bin)."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
