#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile
import tempfile
import subprocess
import pytest

ARCHIVES_DIR = "/home/user/archives"
EXTRACTED_DIR = "/home/user/extracted"
SUMMARY_FILE = "/home/user/docs_summary.txt"

VALID_ARCHIVES = [
    "arch_alpha.tar.gz",
    "arch_beta.tar.gz",
    "arch_gamma.tar.gz"
]

def get_entry_point(bin_path):
    result = subprocess.run(["readelf", "-h", bin_path], capture_output=True, text=True, check=True)
    for line in result.stdout.splitlines():
        if "Entry point address:" in line:
            return line.split(":")[1].strip()
    return ""

def test_docs_summary_exists():
    assert os.path.isfile(SUMMARY_FILE), f"The summary file {SUMMARY_FILE} does not exist."

def test_docs_summary_content():
    assert os.path.isfile(SUMMARY_FILE), f"The summary file {SUMMARY_FILE} does not exist."

    expected_lines = []
    for arch in VALID_ARCHIVES:
        arch_path = os.path.join(ARCHIVES_DIR, arch)
        assert os.path.isfile(arch_path), f"Expected archive {arch_path} is missing."

        with tarfile.open(arch_path, "r:gz") as tar:
            # Get first line of readme.md
            readme_file = tar.extractfile("readme.md")
            assert readme_file is not None, f"readme.md missing in {arch}"
            first_line = readme_file.readline().decode("utf-8").strip()

            # Extract app.bin to a temp directory to run readelf
            with tempfile.TemporaryDirectory() as tmpdir:
                tar.extract("app.bin", path=tmpdir)
                bin_path = os.path.join(tmpdir, "app.bin")
                entry_point = get_entry_point(bin_path)

            expected_lines.append(f"{arch} | {first_line} | {entry_point}")

    expected_lines.sort()

    with open(SUMMARY_FILE, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {SUMMARY_FILE}, found {len(actual_lines)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} in {SUMMARY_FILE} does not match expected output.\n"
            f"Expected: {expected}\n"
            f"Actual:   {actual}"
        )

def test_all_valid_archives_were_extracted():
    assert os.path.isdir(EXTRACTED_DIR), f"The extraction directory {EXTRACTED_DIR} does not exist."
    assert not os.path.islink(EXTRACTED_DIR), f"{EXTRACTED_DIR} must be a real directory, not a symlink."

    extracted_pairs = []
    for root, dirs, files in os.walk(EXTRACTED_DIR, followlinks=False):
        if "readme.md" not in files or "app.bin" not in files:
            continue

        readme_path = os.path.join(root, "readme.md")
        app_path = os.path.join(root, "app.bin")
        if os.path.islink(readme_path) or os.path.islink(app_path):
            continue
        if not os.path.isfile(readme_path) or not os.path.isfile(app_path):
            continue

        with open(readme_path, "rb") as f:
            readme_data = f.read()
        with open(app_path, "rb") as f:
            app_data = f.read()
        extracted_pairs.append((root, readme_data, app_data, app_path))

    for arch in VALID_ARCHIVES:
        arch_path = os.path.join(ARCHIVES_DIR, arch)
        with tarfile.open(arch_path, "r:gz") as tar:
            readme_member = tar.extractfile("readme.md")
            app_member = tar.extractfile("app.bin")
            assert readme_member is not None, f"readme.md missing in {arch}"
            assert app_member is not None, f"app.bin missing in {arch}"
            expected_readme = readme_member.read()
            expected_app = app_member.read()

        matches = [
            pair for pair in extracted_pairs
            if pair[1] == expected_readme and pair[2] == expected_app
        ]
        assert matches, (
            f"The complete readme.md and app.bin contents from {arch} were not found "
            f"together under {EXTRACTED_DIR}."
        )

        extracted_app = matches[0][3]
        assert get_entry_point(extracted_app), (
            f"The extracted app.bin for {arch} is not readable as an ELF executable by readelf."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
