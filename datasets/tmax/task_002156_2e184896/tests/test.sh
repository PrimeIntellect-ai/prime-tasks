#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import pytest

def test_unsafe_links_log():
    log_path = "/home/user/unsafe_links.log"
    assert os.path.isfile(log_path), f"{log_path} is missing."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "/home/user/source_data/dirA/unsafe_link2.txt",
        "/home/user/source_data/unsafe_link1.txt"
    ]

    assert lines == expected_lines, f"Contents of {log_path} do not match the expected sorted unsafe links."

def test_manifest_txt():
    manifest_path = "/home/user/manifest.txt"
    assert os.path.isfile(manifest_path), f"{manifest_path} is missing."

    archive_prep = "/home/user/archive_prep"
    expected_manifest = []

    # Compute expected manifest dynamically based on what should be in archive_prep
    files_to_hash = [
        "./dirA/file2.txt",
        "./dirC/file3.txt",
        "./file1.txt"
    ]

    for rel_path in files_to_hash:
        abs_path = os.path.join(archive_prep, rel_path[2:])
        assert os.path.isfile(abs_path), f"Expected regular file missing in archive_prep: {abs_path}"

        with open(abs_path, "rb") as f:
            file_hash = hashlib.md5(f.read()).hexdigest()
        expected_manifest.append(f"{file_hash}  {rel_path}")

    expected_manifest.sort(key=lambda line: line.split("  ", 1)[1])

    with open(manifest_path, "r") as f:
        actual_manifest = [line.strip() for line in f if line.strip()]

    assert actual_manifest == expected_manifest, f"Contents of {manifest_path} do not match the expected MD5 manifest."

def test_hardlinks():
    files = [
        ("file1.txt", "file1.txt"),
        ("dirA/file2.txt", "dirA/file2.txt"),
        ("dirC/file3.txt", "dirC/file3.txt")
    ]

    for src_rel, prep_rel in files:
        src_path = os.path.join("/home/user/source_data", src_rel)
        prep_path = os.path.join("/home/user/archive_prep", prep_rel)

        assert os.path.isfile(prep_path), f"File missing in archive_prep: {prep_path}"
        assert not os.path.islink(prep_path), f"File in archive_prep should be a hardlink, not a symlink: {prep_path}"

        src_stat = os.stat(src_path)
        prep_stat = os.stat(prep_path)

        assert src_stat.st_ino == prep_stat.st_ino, f"{prep_path} is not a hardlink to {src_path} (inode mismatch)"
        assert src_stat.st_dev == prep_stat.st_dev, f"{prep_path} and {src_path} are on different devices"

def test_safe_symlinks():
    links = [
        ("dirA/dirB/safe_link1.txt", "../file2.txt"),
        ("dirC/safe_link2.txt", "../file1.txt")
    ]

    for link_rel, expected_target in links:
        prep_path = os.path.join("/home/user/archive_prep", link_rel)

        assert os.path.islink(prep_path), f"Expected symlink missing or is not a symlink: {prep_path}"

        actual_target = os.readlink(prep_path)
        assert actual_target == expected_target, f"Symlink {prep_path} points to {actual_target}, expected relative target {expected_target}"

def test_unsafe_symlinks_not_copied():
    unsafe_links = [
        "unsafe_link1.txt",
        "dirA/unsafe_link2.txt"
    ]

    for link_rel in unsafe_links:
        prep_path = os.path.join("/home/user/archive_prep", link_rel)
        assert not os.path.exists(prep_path) and not os.path.islink(prep_path), f"Unsafe link should not exist in archive_prep: {prep_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
