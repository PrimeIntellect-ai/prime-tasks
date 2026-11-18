#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import shutil
import subprocess
import tempfile
import pytest


def test_chunker_source_compiles_and_runs():
    source_path = "/home/user/chunker.c"
    chunks_dir = "/home/user/chunks"

    assert os.path.exists(source_path), f"C source file {source_path} is missing."
    assert os.path.isfile(source_path), f"{source_path} should be a regular file."

    build_dir = tempfile.mkdtemp(prefix="chunker_verify_")
    executable = os.path.join(build_dir, "chunker")
    try:
        compile_result = subprocess.run(
            ["gcc", "-std=c11", source_path, "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "chunker.c failed to compile:\n" + compile_result.stderr
        )

        # Remove prior artifacts so the validated outputs must be produced by
        # the compiled C program during verification.
        if os.path.lexists(chunks_dir):
            if os.path.isdir(chunks_dir) and not os.path.islink(chunks_dir):
                shutil.rmtree(chunks_dir)
            else:
                os.unlink(chunks_dir)

        run_result = subprocess.run(
            [executable],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert run_result.returncode == 0, (
            "Compiled chunker program failed when executed:\n"
            + run_result.stderr
        )
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)


def test_archive_exists():
    archive_path = "/home/user/archive.dat"
    assert os.path.exists(archive_path), f"Input file {archive_path} is missing."
    assert os.path.isfile(archive_path), f"{archive_path} should be a file."


def test_chunks_directory_exists():
    chunks_dir = "/home/user/chunks"
    assert os.path.exists(chunks_dir), f"Directory {chunks_dir} is missing."
    assert os.path.isdir(chunks_dir), f"{chunks_dir} should be a directory."


def test_manifest_and_chunks():
    archive_path = "/home/user/archive.dat"
    chunks_dir = "/home/user/chunks"
    manifest_path = os.path.join(chunks_dir, "manifest.txt")

    assert os.path.exists(archive_path), f"Archive {archive_path} missing."
    assert os.path.exists(manifest_path), f"Manifest file {manifest_path} missing."

    with open(archive_path, 'rb') as f:
        data = f.read()

    expected_manifest = []
    for i in range(0, len(data), 4096):
        chunk = data[i:i+4096]
        xor_sum = 0
        for b in chunk:
            xor_sum ^= b
        idx = i // 4096
        expected_manifest.append(f"chunk_{idx:04d}.dat {len(chunk)} {xor_sum:02x}")

    with open(manifest_path, 'r') as f:
        actual_manifest = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_manifest == expected_manifest, (
        f"Manifest mismatch.\nExpected:\n{expected_manifest}\nGot:\n{actual_manifest}"
    )

    # Verify chunk contents
    for i in range(0, len(data), 4096):
        idx = i // 4096
        chunk = data[i:i+4096]
        chunk_path = os.path.join(chunks_dir, f"chunk_{idx:04d}.dat")
        assert os.path.exists(chunk_path), f"Chunk {chunk_path} missing"
        with open(chunk_path, 'rb') as f:
            c_data = f.read()
        assert c_data == chunk, f"Data mismatch in chunk_{idx:04d}.dat"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
