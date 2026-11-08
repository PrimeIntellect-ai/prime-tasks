#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import struct
import subprocess
import tempfile
import uuid
import pytest

ARCHIVER = "/home/user/archiver"
SOURCE = "/home/user/archiver.c"
ARCHIVE = "/home/user/output.archive"
CONFIG = "/home/user/archive.conf"


def parse_archive(path):
    with open(path, "rb") as f:
        data = f.read()

    assert data.startswith(b"RLE_ARC\n"), "Archive does not start with the correct global header 'RLE_ARC\\n'."
    offset = 8
    entries = []

    while offset < len(data):
        if offset + 2 > len(data):
            pytest.fail("Archive truncated while reading path length.")
        path_len = struct.unpack_from("<H", data, offset)[0]
        offset += 2

        if offset + path_len > len(data):
            pytest.fail("Archive truncated while reading path string.")
        path_bytes = data[offset:offset + path_len]
        try:
            path_str = path_bytes.decode("ascii")
        except UnicodeDecodeError:
            pytest.fail("Archive contains a non-ASCII path.")
        offset += path_len

        decoded = bytearray()
        pairs = []
        while True:
            if offset + 2 > len(data):
                pytest.fail(f"Archive truncated while reading RLE data for {path_str}.")
            count = data[offset]
            value = data[offset + 1]
            offset += 2
            if count == 0 and value == 0:
                break
            if count == 0:
                pytest.fail(f"Invalid RLE count 0 (other than EOF marker) for {path_str}.")
            pairs.append((count, value))
            decoded.extend([value] * count)

        entries.append((path_str, bytes(decoded), pairs))

    return entries


def canonical_rle(content):
    result = []
    i = 0
    while i < len(content):
        value = content[i]
        run = 1
        while i + run < len(content) and content[i + run] == value:
            run += 1
        remaining = run
        while remaining:
            count = min(remaining, 255)
            result.append((count, value))
            remaining -= count
        i += run
    return result


def run_archiver(binary):
    if os.path.exists(ARCHIVE):
        os.unlink(ARCHIVE)
    subprocess.run([binary], cwd="/home/user", check=True, timeout=8)
    assert os.path.isfile(ARCHIVE), f"{binary} did not generate {ARCHIVE}."


def test_archiver_files_exist():
    assert os.path.isfile(SOURCE), "Source file /home/user/archiver.c is missing."
    assert os.path.isfile(ARCHIVER), "Executable /home/user/archiver is missing."
    assert os.access(ARCHIVER, os.X_OK), "/home/user/archiver is not executable."
    with open(ARCHIVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/archiver is not a compiled ELF executable."


def test_output_archive_format_and_contents():
    archive_path = ARCHIVE
    assert os.path.isfile(archive_path), f"Output archive {archive_path} is missing."

    # The submitted executable must actually regenerate the requested archive.
    subprocess.run([ARCHIVER], cwd="/home/user", check=True, timeout=8)

    with open(archive_path, "rb") as f:
        data = f.read()

    assert data.startswith(b"RLE_ARC\n"), "Archive does not start with the correct global header 'RLE_ARC\\n'."

    offset = 8
    archived_files = {}

    while offset < len(data):
        if offset + 2 > len(data):
            pytest.fail("Archive truncated while reading path length.")

        path_len = struct.unpack_from("<H", data, offset)[0]
        offset += 2

        if offset + path_len > len(data):
            pytest.fail("Archive truncated while reading path string.")

        path_bytes = data[offset:offset+path_len]
        path_str = path_bytes.decode('ascii', errors='replace')
        offset += path_len

        decoded_content = bytearray()
        while True:
            if offset + 2 > len(data):
                pytest.fail(f"Archive truncated while reading RLE data for {path_str}.")

            count = data[offset]
            value = data[offset+1]
            offset += 2

            if count == 0 and value == 0:
                break

            if count == 0:
                pytest.fail(f"Invalid RLE count 0 (other than EOF marker) for {path_str}.")

            decoded_content.extend([value] * count)

        archived_files[path_str] = bytes(decoded_content)

    expected_files = {
        "project_alpha/file1.txt": b"AAAAABBBCC",
        "project_beta/file2.txt": b"Hello World!"
    }

    assert len(archived_files) == len(expected_files), f"Expected exactly {len(expected_files)} files in archive, found {len(archived_files)}."

    for expected_path, expected_content in expected_files.items():
        assert expected_path in archived_files, f"Expected file {expected_path} not found in archive."
        assert archived_files[expected_path] == expected_content, f"Decoded content for {expected_path} does not match expected."


def test_dynamic_traversal_deduplication_and_rle():
    token = uuid.uuid4().hex
    base = f"/home/user/verifier_case_{token}"
    root_a = os.path.join(base, "root_a")
    root_b = os.path.join(base, "root_b")
    external = os.path.join(base, "external")
    os.makedirs(os.path.join(root_a, "sub"))
    os.makedirs(os.path.join(root_b, "nested"))
    os.makedirs(external)

    long_path = os.path.join(root_a, f"long_{token}.bin")
    random_path = os.path.join(root_b, "nested", f"random_{token}.bin")
    empty_path = os.path.join(root_a, f"empty_{token}.dat")
    external_path = os.path.join(external, f"linked_{token}.txt")

    contents = {
        long_path: b"Q" * 300 + b"R" * 255 + b"R" * 2 + b"\x00" * 4 + b"tail",
        random_path: os.urandom(193) + b"Z" * 260,
        empty_path: b"",
        external_path: b"through-a-directory-symlink\n" + token.encode("ascii"),
    }
    for path, content in contents.items():
        with open(path, "wb") as f:
            f.write(content)

    # Multiple names for one inode, directory aliases, and genuine loops.
    os.link(long_path, os.path.join(root_b, f"hard_alias_{token}.bin"))
    os.symlink(root_a, os.path.join(root_a, "sub", "back_to_root_a"))
    os.symlink(root_a, os.path.join(root_b, "link_to_root_a"))
    os.symlink(external, os.path.join(root_a, "link_to_external"))

    with open(CONFIG, "rb") as f:
        original_config = f.read()

    compiled = os.path.join(tempfile.gettempdir(), f"archiver_from_source_{token}")
    expected_by_inode = {}
    for path, content in contents.items():
        st = os.stat(path)
        expected_by_inode[(st.st_dev, st.st_ino)] = content

    def validate(binary):
        run_archiver(binary)
        entries = parse_archive(ARCHIVE)
        assert len(entries) == len(expected_by_inode), (
            f"Expected exactly {len(expected_by_inode)} unique regular files, found {len(entries)}."
        )

        seen_paths = set()
        seen_inodes = set()
        for relpath, decoded, pairs in entries:
            assert relpath not in seen_paths, f"Duplicate archive path {relpath}."
            seen_paths.add(relpath)
            assert relpath and not os.path.isabs(relpath), f"Invalid relative path {relpath!r}."
            assert os.path.normpath(relpath) == relpath and not relpath.startswith("../"), (
                f"Unsafe or non-normalized archive path {relpath!r}."
            )

            disk_path = os.path.join("/home/user", relpath)
            assert os.path.isfile(disk_path), f"Archived path {relpath} is not a reachable regular file."
            st = os.stat(disk_path)
            inode = (st.st_dev, st.st_ino)
            assert inode in expected_by_inode, f"Unexpected file {relpath} was archived."
            assert inode not in seen_inodes, f"The same regular file was archived more than once ({relpath})."
            seen_inodes.add(inode)

            expected_content = expected_by_inode[inode]
            assert decoded == expected_content, f"Decoded content for {relpath} is incorrect."
            assert pairs == canonical_rle(expected_content), f"RLE stream for {relpath} is not correctly generated."

        assert seen_inodes == set(expected_by_inode), "Not all reachable unique regular files were archived."

    try:
        with open(CONFIG, "w", encoding="ascii") as f:
            f.write(root_a + "\n\n" + root_b + "\n")

        # Exercise the demanded executable, including loop handling and dynamic data.
        validate(ARCHIVER)

        # Independently compile and exercise the submitted C source as well.
        subprocess.run(["cc", SOURCE, "-o", compiled], check=True, timeout=15)
        validate(compiled)
    finally:
        with open(CONFIG, "wb") as f:
            f.write(original_config)
        if os.path.exists(compiled):
            os.unlink(compiled)
        shutil.rmtree(base, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
