#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import subprocess
import pytest

EXECUTABLE = "/home/user/archive_docs"
INPUT_DIR = "/home/user/docs_input"
OUTPUT_DIR = "/home/user/docs_output"


def run_archiver():
    result = subprocess.run(
        [EXECUTABLE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"archive_docs exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def reset_output():
    shutil.rmtree(OUTPUT_DIR, ignore_errors=True)


def encode_rle(data):
    out = bytearray()
    if not data:
        return bytes(out)
    current = data[0]
    count = 1
    for value in data[1:]:
        if value == current and count < 255:
            count += 1
        else:
            out.extend((count, current))
            current = value
            count = 1
    out.extend((count, current))
    return bytes(out)


def expected_chunks(data):
    return [data[i:i + 512] for i in range(0, len(data), 512)]


@pytest.fixture(scope="module", autouse=True)
def execute_on_original_fixture():
    reset_output()
    run_archiver()


def test_executable_exists():
    executable_path = "/home/user/archive_docs"
    assert os.path.isfile(executable_path), f"Executable {executable_path} is missing."
    assert os.access(executable_path, os.X_OK), f"Executable {executable_path} is not executable."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "archive_docs must be a compiled native executable."


def test_manifest_content():
    manifest_path = "/home/user/docs_output/manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing."

    with open(manifest_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "/home/user/docs_input/module_a/intro.txt",
        "/home/user/docs_input/module_b/submodule/details.txt",
        "/home/user/docs_input/module_c/long.txt"
    ]

    assert lines == expected_lines, f"Manifest contents do not match expected sorted unique absolute paths. Got: {lines}"


def test_chunk_content():
    chunk_path = "/home/user/docs_output/chunk_0000.dat"
    assert os.path.isfile(chunk_path), f"Chunk file {chunk_path} is missing."

    with open(chunk_path, "rb") as f:
        data = f.read()

    expected_data = bytes([
        0x05, ord('A'),
        0x05, ord('B'),
        0x05, ord('C'),
        0x05, ord('D'),
        0x05, ord('E'),
        0x05, ord('F'),
        0xFF, ord('G'),
        0x2D, ord('G')
    ])

    assert data == expected_data, f"Chunk data does not match expected RLE byte stream. Got: {data.hex()}"


def test_no_extra_chunks():
    output_dir = "/home/user/docs_output"
    chunk_files = [f for f in os.listdir(output_dir) if f.startswith("chunk_") and f.endswith(".dat")]

    assert len(chunk_files) == 1, f"Expected exactly 1 chunk file, but found {len(chunk_files)}: {chunk_files}"
    assert chunk_files[0] == "chunk_0000.dat", f"Unexpected chunk file name: {chunk_files[0]}"


def test_z_dynamic_execution_traversal_rle_and_chunking():
    shutil.rmtree(INPUT_DIR, ignore_errors=True)
    reset_output()
    os.makedirs(INPUT_DIR)

    token = secrets.token_hex(6)
    dirs = [
        os.path.join(INPUT_DIR, token + "_a"),
        os.path.join(INPUT_DIR, token + "_b", "nested"),
        os.path.join(INPUT_DIR, token + "_c"),
    ]
    for directory in dirs:
        os.makedirs(directory, exist_ok=True)

    targets = [
        os.path.join(dirs[0], "first.txt"),
        os.path.join(dirs[1], "second.txt"),
        os.path.join(dirs[2], "third.txt"),
    ]
    targets = sorted(os.path.realpath(path) for path in targets)

    rng = random.SystemRandom()
    alphabet = b"ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz0123456789"

    def alternating(length, previous=None):
        result = bytearray()
        last = previous
        for _ in range(length):
            choices = [c for c in alphabet if c != last]
            value = rng.choice(choices)
            result.append(value)
            last = value
        return bytes(result)

    run_byte = rng.choice(alphabet)
    first = bytes([run_byte]) * rng.randint(270, 390) + alternating(430, run_byte)
    second = bytes([first[-1]]) * rng.randint(275, 360) + alternating(420, first[-1])
    third = alternating(520, second[-1])
    contents = [first, second, third]

    for path, content in zip(targets, contents):
        with open(path, "wb") as f:
            f.write(content)

    # Duplicate file symlinks must not cause duplicate archive entries.
    os.symlink(targets[0], os.path.join(dirs[2], "duplicate_first.txt"))
    os.symlink(targets[1], os.path.join(dirs[0], "duplicate_second.txt"))

    # Directory aliases and cycles must be followed safely without reprocessing.
    os.symlink(dirs[1], os.path.join(dirs[2], "linked_directory"))
    os.symlink(dirs[0], os.path.join(dirs[0], "self_loop"))
    os.symlink(INPUT_DIR, os.path.join(dirs[1], "root_loop"))

    with open(os.path.join(INPUT_DIR, token + "_ignored.bin"), "wb") as f:
        f.write(b"THIS MUST NOT BE ARCHIVED")
    os.symlink(os.path.join(INPUT_DIR, "missing.txt"), os.path.join(dirs[0], "broken.txt"))

    merged = b"".join(content for _, content in sorted(zip(targets, contents)))
    compressed = encode_rle(merged)
    chunks = expected_chunks(compressed)
    assert len(chunks) >= 2, "Internal test fixture failed to require multiple chunks."

    run_archiver()

    manifest_path = os.path.join(OUTPUT_DIR, "manifest.txt")
    assert os.path.isfile(manifest_path), "Dynamic run did not create manifest.txt."
    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest_lines = [line.strip() for line in f if line.strip()]
    assert manifest_lines == targets, (
        f"Dynamic manifest is not the sorted set of unique resolved targets: {manifest_lines}"
    )

    actual_chunk_names = sorted(
        name for name in os.listdir(OUTPUT_DIR)
        if name.startswith("chunk_") and name.endswith(".dat")
    )
    expected_names = [f"chunk_{i:04d}.dat" for i in range(len(chunks))]
    assert actual_chunk_names == expected_names, (
        f"Incorrect dynamic chunk set: expected {expected_names}, got {actual_chunk_names}"
    )

    for name, expected in zip(expected_names, chunks):
        with open(os.path.join(OUTPUT_DIR, name), "rb") as f:
            actual = f.read()
        assert actual == expected, f"Incorrect data in {name}."
        if name != expected_names[-1]:
            assert len(actual) == 512, f"Non-final chunk {name} is not exactly 512 bytes."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
