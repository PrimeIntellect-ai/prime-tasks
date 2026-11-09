#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import hashlib
import pytest

DUMP_DIR = "/home/user/project_dump"

EXPECTED_CONTENTS = {
    "archive.gz": b"\x1F\x8B\x08\x00\x00\x00\x00\x00\x00\x03\x4B\xCB\xCF\x07\x00",
    "document.pdf": b"\x25\x50\x44\x46\x2D\x31\x2E\x34\x0A\x25\xE2\xE3\xCF\xD3",
    "logo.png": b"\x89\x50\x4E\x47\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52",
    "notes.txt": b"This is just a standard text file.\nNothing special here.\n",
}

SIGNATURES = {
    "archive.gz": b"\x1F\x8B",
    "document.pdf": b"\x25\x50\x44\x46\x2D",
    "logo.png": b"\x89\x50\x4E\x47\x0D\x0A\x1A\x0A",
}


def test_old_files_removed():
    old_files = ["logo.dat", "archive.tmp", "document", "notes.bin"]
    for f in old_files:
        path = os.path.join(DUMP_DIR, f)
        assert not os.path.exists(path), f"Old file {path} should have been renamed/removed."


def test_new_files_exist():
    new_files = ["archive.gz", "document.pdf", "logo.png", "notes.txt"]
    for f in new_files:
        path = os.path.join(DUMP_DIR, f)
        assert os.path.isfile(path), f"Expected new file {path} is missing. Was it correctly renamed?"


def test_original_contents_preserved_and_signatures_match():
    for filename, expected in EXPECTED_CONTENTS.items():
        path = os.path.join(DUMP_DIR, filename)
        assert os.path.isfile(path), f"Expected renamed file {path} is missing."
        with open(path, "rb") as file_obj:
            actual = file_obj.read()
        assert actual == expected, f"Contents of {filename} were not preserved during rename."

    for filename, signature in SIGNATURES.items():
        assert EXPECTED_CONTENTS[filename].startswith(signature)

    known_signatures = tuple(SIGNATURES.values())
    assert not EXPECTED_CONTENTS["notes.txt"].startswith(known_signatures), "notes.txt is not plain text."


def test_only_expected_final_files_exist():
    expected = set(EXPECTED_CONTENTS) | {"manifest.sha256"}
    actual = set(os.listdir(DUMP_DIR))
    assert actual == expected, f"Unexpected final directory contents: {sorted(actual)}"


def test_manifest_exists_and_correct():
    manifest_path = os.path.join(DUMP_DIR, "manifest.sha256")
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing."

    new_files = ["archive.gz", "document.pdf", "logo.png", "notes.txt"]
    expected_lines = []

    for f in sorted(new_files):
        path = os.path.join(DUMP_DIR, f)
        # We only compute checksum if the file exists to avoid crashing the test
        # if the previous test failed, though pytest will report this anyway.
        if os.path.isfile(path):
            with open(path, "rb") as file_obj:
                checksum = hashlib.sha256(file_obj.read()).hexdigest()
            expected_lines.append(f"{checksum}  {f}")

    expected_content = "\n".join(expected_lines)

    with open(manifest_path, "r", encoding="utf-8") as m:
        actual_content = m.read().strip()

    assert actual_content == expected_content, "Manifest contents do not match expected checksums, format, or sorting."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
