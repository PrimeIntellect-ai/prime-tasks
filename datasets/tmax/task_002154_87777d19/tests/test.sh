#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

ORGANIZED_DOCS_DIR = "/home/user/organized_docs"
RAW_ASSETS_DIR = "/home/user/legacy_docs/raw_assets"

EXPECTED_SYMLINKS = {
    "pdfs/item_01.tmp.pdf": "item_01.tmp",
    "pngs/data_02.bin.png": "data_02.bin",
    "jpegs/img_03.dat.jpg": "img_03.dat",
    "pngs/pic_06.var.png": "pic_06.var",
}

def test_directories_exist():
    assert os.path.isdir(ORGANIZED_DOCS_DIR), f"Directory {ORGANIZED_DOCS_DIR} is missing."
    for subdir in ["pdfs", "pngs", "jpegs"]:
        path = os.path.join(ORGANIZED_DOCS_DIR, subdir)
        assert os.path.isdir(path), f"Subdirectory {path} is missing."

def test_symlinks_exist_and_correct():
    for rel_link, orig_file in EXPECTED_SYMLINKS.items():
        link_path = os.path.join(ORGANIZED_DOCS_DIR, rel_link)
        target_path = os.path.join(RAW_ASSETS_DIR, orig_file)

        assert os.path.islink(link_path), f"Expected symlink at {link_path} is missing or not a symlink."

        actual_target = os.readlink(link_path)
        assert actual_target == target_path, f"Symlink {link_path} points to {actual_target}, expected {target_path}."

def test_no_extra_files_in_subdirs():
    expected_paths = set(os.path.join(ORGANIZED_DOCS_DIR, p) for p in EXPECTED_SYMLINKS.keys())

    actual_paths = set()
    for subdir in ["pdfs", "pngs", "jpegs"]:
        subdir_path = os.path.join(ORGANIZED_DOCS_DIR, subdir)
        if os.path.isdir(subdir_path):
            for f in os.listdir(subdir_path):
                actual_paths.add(os.path.join(subdir_path, f))

    extra_files = actual_paths - expected_paths
    assert not extra_files, f"Found unexpected files/links in subdirectories: {extra_files}"

def test_summary_log():
    summary_path = os.path.join(ORGANIZED_DOCS_DIR, "summary.txt")
    assert os.path.isfile(summary_path), f"Log file {summary_path} is missing."

    expected_lines = sorted(os.path.join(ORGANIZED_DOCS_DIR, p) for p in EXPECTED_SYMLINKS.keys())

    with open(summary_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"Contents of {summary_path} do not match expected sorted list of symlinks. Expected: {expected_lines}, Got: {actual_lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
