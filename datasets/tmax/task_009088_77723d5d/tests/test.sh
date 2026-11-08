#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import os
import random
import secrets
import struct
import subprocess
import tarfile
import tempfile
import zipfile


def expected_artifacts():
    random.seed(42)
    blob1 = bytes(random.getrandbits(8) for _ in range(3500))
    payload = bytes(random.getrandbits(8) for _ in range(2048))
    return {
        "blob1.bin": blob1,
        "configs/sys.conf": b"system_mode=production\n",
        "data_payload.bin": payload,
    }


def encode_archive(entries):
    result = bytearray(b"ARTF")
    for path, data in entries:
        path_bytes = path.encode("utf-8")
        chunks = [data[i:i + 1024] for i in range(0, len(data), 1024)]
        result += struct.pack("=H", len(path_bytes))
        result += path_bytes
        result += struct.pack("=I", len(chunks))
        for chunk in chunks:
            result += struct.pack("=H", len(chunk))
            result += chunk
    return bytes(result)


def test_original_bundle_and_extracted_files_are_correct():
    expected = expected_artifacts()
    bundle_path = "/home/user/repo/bundle.tar.gz"
    assert os.path.isfile(bundle_path), f"Bundle {bundle_path} does not exist."

    with tarfile.open(bundle_path, "r:gz") as tf:
        files = {m.name: m for m in tf.getmembers() if m.isfile()}
        assert set(files) == {"blob1.bin", "nested.zip"}, f"Unexpected bundle members: {set(files)}"
        blob = tf.extractfile(files["blob1.bin"])
        nested = tf.extractfile(files["nested.zip"])
        assert blob is not None and blob.read() == expected["blob1.bin"], "blob1.bin in bundle is incorrect."
        assert nested is not None
        nested_bytes = nested.read()

    with zipfile.ZipFile(io.BytesIO(nested_bytes), "r") as zf:
        names = set(zf.namelist())
        assert names == {"configs/sys.conf", "data_payload.bin"}, f"Unexpected nested.zip members: {names}"
        assert zf.read("configs/sys.conf") == expected["configs/sys.conf"], "configs/sys.conf in nested.zip is incorrect."
        assert zf.read("data_payload.bin") == expected["data_payload.bin"], "data_payload.bin in nested.zip is incorrect."

    for relative_path, expected_data in expected.items():
        extracted_path = os.path.join("/home/user/unpacked", relative_path)
        assert os.path.isfile(extracted_path), f"Expected unpacked file {extracted_path} is missing."
        with open(extracted_path, "rb") as f:
            assert f.read() == expected_data, f"Extracted file {relative_path} does not match the supplied artifact."


def test_clean_manifest_exists_and_correct():
    path = "/home/user/clean_manifest.txt"
    assert os.path.isfile(path), f"Clean manifest {path} does not exist."

    with open(path, "r") as f:
        lines = f.read().splitlines()

    expected_lines = ["blob1.bin", "configs/sys.conf", "data_payload.bin"]
    assert lines == expected_lines, f"Clean manifest contents are incorrect. Expected {expected_lines}, got {lines}"


def test_archiver_source_binary_and_behavior():
    source_path = "/home/user/archiver.c"
    executable_path = "/home/user/archiver"
    assert os.path.isfile(source_path), f"C source {source_path} does not exist."
    assert os.path.isfile(executable_path), f"Compiled archiver {executable_path} does not exist."
    assert os.access(executable_path, os.X_OK), f"Archiver {executable_path} is not executable."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Archiver is not a compiled ELF executable."

    token = secrets.token_hex(8)
    paths = [f"{token}.bin", f"sub_{token}/payload.dat", f"sub_{token}/small.cfg"]
    data = [os.urandom(3073), os.urandom(2048), os.urandom(37)]

    with tempfile.TemporaryDirectory(prefix="verify_archiver_") as temp_dir:
        base_dir = os.path.join(temp_dir, "base")
        os.makedirs(base_dir)
        for relative_path, contents in zip(paths, data):
            full_path = os.path.join(base_dir, relative_path)
            os.makedirs(os.path.dirname(full_path), exist_ok=True)
            with open(full_path, "wb") as f:
                f.write(contents)

        manifest_path = os.path.join(temp_dir, "manifest.txt")
        output_path = os.path.join(temp_dir, "output.bin")
        with open(manifest_path, "w", encoding="utf-8") as f:
            for relative_path in paths:
                f.write(relative_path + "\n")

        result = subprocess.run(
            [executable_path, manifest_path, base_dir, output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
        assert result.returncode == 0, f"Archiver failed on verifier inputs: {result.stderr.decode(errors='replace')}"
        assert os.path.isfile(output_path), "Archiver did not create its requested output file."
        with open(output_path, "rb") as f:
            actual = f.read()
        expected = encode_archive(list(zip(paths, data)))
        assert actual == expected, "Archiver output is incorrect for independently generated verifier inputs."


def test_repo_archive_bin_structure_and_contents():
    archive_path = "/home/user/repo_archive.bin"
    assert os.path.isfile(archive_path), f"Archive {archive_path} does not exist."

    unpacked_dir = "/home/user/unpacked"
    manifest_files = ["blob1.bin", "configs/sys.conf", "data_payload.bin"]

    with open(archive_path, "rb") as f:
        magic = f.read(4)
        assert magic == b"ARTF", f"Invalid magic bytes in archive. Expected b'ARTF', got {magic}"

        for expected_path in manifest_files:
            path_len_bytes = f.read(2)
            assert len(path_len_bytes) == 2, "Unexpected EOF reading path length."
            path_len = struct.unpack("=H", path_len_bytes)[0]
            assert path_len == len(expected_path), f"Path length mismatch. Expected {len(expected_path)}, got {path_len}"

            path_str_bytes = f.read(path_len)
            assert len(path_str_bytes) == path_len, "Unexpected EOF reading path string."
            path_str = path_str_bytes.decode('utf-8', errors='replace')
            assert path_str == expected_path, f"Path string mismatch. Expected {expected_path}, got {path_str}"

            chunk_count_bytes = f.read(4)
            assert len(chunk_count_bytes) == 4, "Unexpected EOF reading chunk count."
            chunk_count = struct.unpack("=I", chunk_count_bytes)[0]

            actual_file_path = os.path.join(unpacked_dir, expected_path)
            assert os.path.isfile(actual_file_path), f"Expected unpacked file {actual_file_path} is missing."

            with open(actual_file_path, "rb") as af:
                actual_data = af.read()

            expected_chunk_count = (len(actual_data) + 1023) // 1024
            if len(actual_data) == 0:
                expected_chunk_count = 0

            assert chunk_count == expected_chunk_count, f"Chunk count mismatch for {expected_path}. Expected {expected_chunk_count}, got {chunk_count}"

            reconstructed_data = b""
            for i in range(chunk_count):
                chunk_size_bytes = f.read(2)
                assert len(chunk_size_bytes) == 2, f"Unexpected EOF reading chunk size for chunk {i} of {expected_path}."
                chunk_size = struct.unpack("=H", chunk_size_bytes)[0]

                chunk_data = f.read(chunk_size)
                assert len(chunk_data) == chunk_size, f"Unexpected EOF reading chunk data for chunk {i} of {expected_path}."
                reconstructed_data += chunk_data

            assert reconstructed_data == actual_data, f"Data mismatch for {expected_path}. Extracted data does not match original."

        extra_data = f.read(1)
        assert extra_data == b"", "Archive contains trailing data after the expected files."


def test_archive_hash_correct():
    hash_path = "/home/user/archive_hash.txt"
    archive_path = "/home/user/repo_archive.bin"

    assert os.path.isfile(hash_path), f"Hash file {hash_path} does not exist."
    assert os.path.isfile(archive_path), f"Archive {archive_path} does not exist."

    with open(hash_path, "r") as f:
        written_hash = f.read().strip()

    with open(archive_path, "rb") as f:
        actual_hash = hashlib.sha256(f.read()).hexdigest()

    assert written_hash == actual_hash, f"Hash mismatch. File contains {written_hash}, but actual SHA-256 is {actual_hash}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
