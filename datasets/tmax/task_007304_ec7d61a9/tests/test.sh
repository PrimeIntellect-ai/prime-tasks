#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat
import pytest

RECOVERED_DATA_DIR = "/home/user/recovered_data"
BY_TYPE_DIR = "/home/user/by_type"
SUMMARY_FILE = "/home/user/recovery_summary.txt"

EXPECTED_FILES = {
    "chunk_01.png": {"links_to": ["chunk_03.png"]},
    "chunk_02.pdf": {"links_to": ["chunk_06.pdf"]},
    "chunk_03.png": {"links_to": ["chunk_01.png"]},
    "chunk_04.jpg": {"links_to": ["chunk_08.jpg", "chunk_10.jpg"]},
    "chunk_05.elf": {"links_to": ["chunk_09.elf"]},
    "chunk_06.pdf": {"links_to": ["chunk_02.pdf"]},
    "chunk_07.png": {"links_to": []},
    "chunk_08.jpg": {"links_to": ["chunk_04.jpg", "chunk_10.jpg"]},
    "chunk_09.elf": {"links_to": ["chunk_05.elf"]},
    "chunk_10.jpg": {"links_to": ["chunk_04.jpg", "chunk_08.jpg"]},
    "chunk_11": {"links_to": []},
}

EXPECTED_CONTENTS = {
    "chunk_01.png": bytes.fromhex("89504e470001020304"),
    "chunk_02.pdf": bytes.fromhex("255044460001020304"),
    "chunk_03.png": bytes.fromhex("89504e470001020304"),
    "chunk_04.jpg": bytes.fromhex("ffd8ffe00001020304"),
    "chunk_05.elf": bytes.fromhex("7f454c460001020304"),
    "chunk_06.pdf": bytes.fromhex("255044460001020304"),
    "chunk_07.png": bytes.fromhex("89504e479999999999"),
    "chunk_08.jpg": bytes.fromhex("ffd8ffe00001020304"),
    "chunk_09.elf": bytes.fromhex("7f454c460001020304"),
    "chunk_10.jpg": bytes.fromhex("ffd8ffe00001020304"),
    "chunk_11": bytes.fromhex("000000000001020304"),
}

EXPECTED_SYMLINKS = {
    "png/chunk_01.png": "chunk_01.png",
    "png/chunk_07.png": "chunk_07.png",
    "pdf/chunk_02.pdf": "chunk_02.pdf",
    "jpg/chunk_04.jpg": "chunk_04.jpg",
    "elf/chunk_05.elf": "chunk_05.elf",
}

EXPECTED_SUMMARY = [
    "chunk_01.png has 2 links",
    "chunk_02.pdf has 2 links",
    "chunk_04.jpg has 3 links",
    "chunk_05.elf has 2 links",
]

def test_renamed_files_exist():
    assert os.path.isdir(RECOVERED_DATA_DIR), f"Directory {RECOVERED_DATA_DIR} is missing."
    actual_files = set(os.listdir(RECOVERED_DATA_DIR))
    expected_files = set(EXPECTED_FILES.keys())

    missing = expected_files - actual_files
    unexpected = actual_files - expected_files

    assert not missing, f"Missing files in {RECOVERED_DATA_DIR}: {missing}"
    assert not unexpected, f"Unexpected files in {RECOVERED_DATA_DIR}: {unexpected}"

def test_recovered_file_contents():
    for filename, expected_content in EXPECTED_CONTENTS.items():
        filepath = os.path.join(RECOVERED_DATA_DIR, filename)
        assert stat.S_ISREG(os.lstat(filepath).st_mode), f"Recovered entry {filename} must be a regular file."
        with open(filepath, "rb") as f:
            actual_content = f.read()
        assert actual_content == expected_content, f"Recovered file {filename} does not contain the expected bytes."

def test_hard_links():
    for filename, data in EXPECTED_FILES.items():
        filepath = os.path.join(RECOVERED_DATA_DIR, filename)
        st = os.stat(filepath)

        expected_link_count = 1 + len(data["links_to"])
        assert st.st_nlink == expected_link_count, f"File {filename} should have {expected_link_count} hard links, but has {st.st_nlink}."

        for linked_file in data["links_to"]:
            linked_filepath = os.path.join(RECOVERED_DATA_DIR, linked_file)
            linked_st = os.stat(linked_filepath)
            assert st.st_ino == linked_st.st_ino, f"File {filename} and {linked_file} should share the same inode (hard linked)."

def test_symbolic_links_organized():
    assert os.path.isdir(BY_TYPE_DIR), f"Directory {BY_TYPE_DIR} is missing."

    for rel_path, target_file in EXPECTED_SYMLINKS.items():
        symlink_path = os.path.join(BY_TYPE_DIR, rel_path)
        assert os.path.islink(symlink_path), f"Expected symbolic link at {symlink_path}"

        target_path = os.readlink(symlink_path)
        expected_target = os.path.join(RECOVERED_DATA_DIR, target_file)

        # Resolve both paths to absolute paths to compare
        assert os.path.abspath(os.path.join(os.path.dirname(symlink_path), target_path)) == expected_target, \
            f"Symlink {symlink_path} does not point to {expected_target}"

    # Check for unexpected files in by_type
    found_symlinks = []
    for root, _, files in os.walk(BY_TYPE_DIR):
        for f in files:
            rel_dir = os.path.relpath(root, BY_TYPE_DIR)
            found_symlinks.append(os.path.normpath(os.path.join(rel_dir, f)))

    expected_symlinks_norm = [os.path.normpath(p) for p in EXPECTED_SYMLINKS.keys()]
    unexpected_symlinks = set(found_symlinks) - set(expected_symlinks_norm)
    assert not unexpected_symlinks, f"Unexpected files/symlinks found in {BY_TYPE_DIR}: {unexpected_symlinks}"

def test_recovery_summary():
    assert os.path.isfile(SUMMARY_FILE), f"Summary file {SUMMARY_FILE} is missing."

    with open(SUMMARY_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == EXPECTED_SUMMARY, f"Summary file contents do not match expected.\nExpected: {EXPECTED_SUMMARY}\nActual: {lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
