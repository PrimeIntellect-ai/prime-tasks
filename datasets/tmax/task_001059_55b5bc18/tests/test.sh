#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import hashlib
import pytest

CURATED_DIR = "/home/user/artifacts_curated"
MANIFEST_FILE = "/home/user/curation_manifest.txt"

EXPECTED_FILES = {
    b"\x7f\x45\x4c\x46\x01\x02\x03": ".elf",
    b"\x89\x50\x4e\x47\x0d\x0a\x1a\x0a": ".png",
    b"\x1f\x8b\x08\x00\x00\x00\x00\x00": ".gz",
    b"\x50\x4b\x03\x04\x14\x00\x00\x00": ".zip",
    b"\x00\x11\x22\x33\x44\x55": ".bin",
}

def get_expected_state():
    state = {}
    for content, ext in EXPECTED_FILES.items():
        h = hashlib.sha256(content).hexdigest()
        state[h] = (ext, content)
    return state

def test_curated_directory_exists():
    assert os.path.isdir(CURATED_DIR), f"Directory {CURATED_DIR} does not exist."

def test_curated_directory_contents():
    expected_state = get_expected_state()

    files_in_curated = os.listdir(CURATED_DIR)
    assert len(files_in_curated) == 5, f"Expected exactly 5 files in {CURATED_DIR}, found {len(files_in_curated)}."

    for h, (ext, content) in expected_state.items():
        expected_filename = f"{h}{ext}"
        assert expected_filename in files_in_curated, f"Expected file {expected_filename} not found in {CURATED_DIR}."

        filepath = os.path.join(CURATED_DIR, expected_filename)
        with open(filepath, "rb") as f:
            actual_content = f.read()

        assert actual_content == content, f"Content of {expected_filename} does not match the expected bytes."

def test_manifest_file_exists():
    assert os.path.isfile(MANIFEST_FILE), f"Manifest file {MANIFEST_FILE} does not exist."

def test_manifest_contents():
    expected_state = get_expected_state()

    expected_lines = []
    for h, (ext, _) in expected_state.items():
        expected_lines.append(f"{h} {ext}")

    expected_lines.sort()

    with open(MANIFEST_FILE, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == 5, f"Expected exactly 5 lines in {MANIFEST_FILE}, found {len(actual_lines)}."

    assert actual_lines == expected_lines, "Manifest contents do not match expected sorted output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
