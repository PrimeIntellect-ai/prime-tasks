#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_dedup_archive.py
import gzip
import hashlib
import os
import shutil
import stat
import subprocess
import uuid

import pytest

SOURCE = "/home/user/dedup_archive.c"
BINARY = "/home/user/dedup_archive"


def assert_native_executable(path):
    st = os.lstat(path)
    assert stat.S_ISREG(st.st_mode), f"Compiled program is not a regular file: {path}"
    assert os.access(path, os.X_OK), f"Compiled program is not executable: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled program is not an ELF executable: {path}"


def run_program(binary, source, dest, manifest, error_log):
    result = subprocess.run(
        [binary, source, dest, manifest, error_log],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
    assert result.returncode == 0, (
        f"Program exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


@pytest.fixture(scope="session")
def rebuilt_binary(tmp_path_factory):
    assert os.path.isfile(SOURCE), f"C source file missing: {SOURCE}"
    assert stat.S_ISREG(os.lstat(SOURCE).st_mode), f"C source is not a regular file: {SOURCE}"
    assert_native_executable(BINARY)

    output = str(tmp_path_factory.mktemp("build") / "dedup_archive")
    result = subprocess.run(
        ["gcc", "-std=gnu11", "-O2", SOURCE, "-o", output],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, (
        f"dedup_archive.c does not compile. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert_native_executable(output)
    return output


@pytest.fixture(scope="session", autouse=True)
def run_required_invocation(rebuilt_binary):
    dest = "/home/user/archive_dest"
    manifest = "/home/user/manifest.txt"
    error_log = "/home/user/symlink_errors.log"

    shutil.rmtree(dest, ignore_errors=True)
    for path in (manifest, error_log):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    run_program(BINARY, "/home/user/data_source", dest, manifest, error_log)


def test_program_artifacts(rebuilt_binary):
    assert os.path.isfile(SOURCE)
    assert_native_executable(BINARY)
    assert_native_executable(rebuilt_binary)


def test_manifest_file():
    manifest_path = "/home/user/manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file missing: {manifest_path}"

    with open(manifest_path, "r") as f:
        lines = f.read().strip().split("\n")

    expected_lines = [
        "dirA/file2.txt e182e0e02eb7fa01bc6c071bb9cc233d45512b9826f59232eb1e4eb41d5b369c",
        "dirB/dirC/file4.txt 8d6ff06a8e52eec87cd7a7b8e1a1792f3900985ca581b957cf94819779df20bd",
        "dirB/file3.txt 8d6ff06a8e52eec87cd7a7b8e1a1792f3900985ca581b957cf94819779df20bd",
        "file1.txt e182e0e02eb7fa01bc6c071bb9cc233d45512b9826f59232eb1e4eb41d5b369c",
    ]

    assert lines == expected_lines, "Manifest content does not match expected output or is not sorted."


def test_error_log():
    error_log_path = "/home/user/symlink_errors.log"
    assert os.path.isfile(error_log_path), f"Error log missing: {error_log_path}"

    with open(error_log_path, "r") as f:
        lines = [line for line in f.read().splitlines() if line]

    expected_lines = ["/home/user/data_source/dirA/loop1"]
    assert sorted(lines) == expected_lines, "Error log content does not match expected output."


def test_archive_files_and_hardlinks():
    dest_dir = "/home/user/archive_dest"
    assert os.path.isdir(dest_dir), f"Destination directory missing: {dest_dir}"

    file1 = os.path.join(dest_dir, "file1.txt.gz")
    file2 = os.path.join(dest_dir, "dirA/file2.txt.gz")
    file3 = os.path.join(dest_dir, "dirB/file3.txt.gz")
    file4 = os.path.join(dest_dir, "dirB/dirC/file4.txt.gz")

    for path in [file1, file2, file3, file4]:
        assert os.path.isfile(path), f"Archive file missing: {path}"

    stat1 = os.stat(file1)
    stat2 = os.stat(file2)
    stat3 = os.stat(file3)
    stat4 = os.stat(file4)

    assert stat1.st_ino == stat2.st_ino, "file1.txt.gz and file2.txt.gz are not hard linked."
    assert stat3.st_ino == stat4.st_ino, "file3.txt.gz and file4.txt.gz are not hard linked."
    assert stat1.st_nlink == 2, f"Expected 2 hard links for file1.txt.gz, got {stat1.st_nlink}"
    assert stat3.st_nlink == 2, f"Expected 2 hard links for file3.txt.gz, got {stat3.st_nlink}"


def test_gzip_content():
    dest_dir = "/home/user/archive_dest"
    expected_content_1 = b"Hello World! This is a test file for deduplication.\n"
    expected_content_3 = b"Different content for file 3.\n"

    with gzip.open(os.path.join(dest_dir, "file1.txt.gz"), "rb") as f:
        content1 = f.read()
    assert content1 == expected_content_1, "Uncompressed content of file1.txt.gz does not match original."

    with gzip.open(os.path.join(dest_dir, "dirB/file3.txt.gz"), "rb") as f:
        content3 = f.read()
    assert content3 == expected_content_3, "Uncompressed content of file3.txt.gz does not match original."


def test_general_behavior_on_derived_inputs(tmp_path, rebuilt_binary):
    source = tmp_path / "source"
    dest = tmp_path / "dest"
    manifest = tmp_path / "manifest.txt"
    error_log = tmp_path / "errors.txt"

    (source / "alpha" / "nested").mkdir(parents=True)
    (source / "beta").mkdir()

    duplicate = ("duplicate-" + uuid.uuid4().hex).encode() + b"\n"
    unique1 = os.urandom(113)
    unique2 = ("unique-" + uuid.uuid4().hex).encode()

    files = {
        "root.bin": duplicate,
        "alpha/copy.bin": duplicate,
        "alpha/nested/third.bin": duplicate,
        "beta/unique.dat": unique1,
        "alpha/other.txt": unique2,
    }
    for rel, content in files.items():
        path = source / rel
        path.write_bytes(content)

    loop_path = source / "alpha" / "nested" / "ancestor_loop"
    os.symlink(str(source), loop_path)
    os.symlink("../beta", source / "alpha" / "non_loop_directory_link")
    os.symlink("../root.bin", source / "alpha" / "non_loop_file_link")
    os.symlink("missing-target", source / "dangling_link")

    run_program(rebuilt_binary, str(source), str(dest), str(manifest), str(error_log))

    expected_manifest = sorted(
        f"{rel} {hashlib.sha256(content).hexdigest()}" for rel, content in files.items()
    )
    assert manifest.is_file(), "Manifest was not created on a fresh input"
    assert manifest.read_text().splitlines() == expected_manifest

    assert error_log.is_file(), "Error log was not created on a fresh input"
    assert error_log.read_text().splitlines() == [str(loop_path)]

    actual_archives = sorted(
        str(path.relative_to(dest))
        for path in dest.rglob("*")
        if path.is_file()
    )
    expected_archives = sorted(rel + ".gz" for rel in files)
    assert actual_archives == expected_archives, "Archive contains missing or unexpected files"

    for rel, content in files.items():
        archive = dest / (rel + ".gz")
        with gzip.open(archive, "rb") as f:
            assert f.read() == content, f"Wrong compressed content for {rel}"

    duplicate_archives = [
        dest / "root.bin.gz",
        dest / "alpha/copy.bin.gz",
        dest / "alpha/nested/third.bin.gz",
    ]
    duplicate_stats = [os.stat(path) for path in duplicate_archives]
    assert len({st.st_ino for st in duplicate_stats}) == 1, "Duplicate files are not hard linked"
    assert all(st.st_nlink == 3 for st in duplicate_stats), "Duplicate hard-link count is incorrect"

    for rel in ("beta/unique.dat.gz", "alpha/other.txt.gz"):
        assert os.stat(dest / rel).st_nlink == 1, f"Unique file {rel} was incorrectly linked"
TEST_EOF

if python3 -m pytest /tmp/test_dedup_archive.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
