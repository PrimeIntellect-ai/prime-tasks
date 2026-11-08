#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import zipfile
import tarfile
import pytest

ARTIFACTS_DIR = "/home/user/artifacts"
CURATED_DIR = "/home/user/curated_artifacts"
REPORT_FILE = "/home/user/curation_report.txt"

EXPECTED_FILES = [
    "app1.zip",
    "app2.tar.gz",
    "app3.zip",
    "app4.tar.gz"
]

def read_archive_file(directory, filename, inner_file):
    filepath = os.path.join(directory, filename)
    if filename.endswith(".zip"):
        with zipfile.ZipFile(filepath, "r") as zf:
            return zf.read(inner_file)
    elif filename.endswith(".tar.gz"):
        with tarfile.open(filepath, "r:gz") as tf:
            member = tf.extractfile(inner_file)
            assert member is not None, f"{inner_file} is not a regular file in {filename}"
            return member.read()
    raise AssertionError(f"Unsupported archive format: {filename}")

def get_original_data(filename):
    return read_archive_file(ARTIFACTS_DIR, filename, "data.bin")

def read_curated_file(filename, inner_file):
    return read_archive_file(CURATED_DIR, filename, inner_file)

def manifest_lines(content):
    # The supplied manifests use literal backslash-n field separators. Accept
    # those as separators while also handling ordinary newline-separated text.
    return content.replace(b"\\n", b"\n").split(b"\n")

def test_curated_directory_exists():
    assert os.path.isdir(CURATED_DIR), f"Directory {CURATED_DIR} does not exist."

@pytest.mark.parametrize("filename", EXPECTED_FILES)
def test_curated_files_exist(filename):
    filepath = os.path.join(CURATED_DIR, filename)
    assert os.path.isfile(filepath), f"Expected curated artifact {filepath} does not exist."

def test_report_content():
    assert os.path.isfile(REPORT_FILE), f"Report file {REPORT_FILE} does not exist."
    with open(REPORT_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "[Modified] app1.zip",
        "[Modified] app2.tar.gz",
        "[Unchanged] app3.zip",
        "[Unchanged] app4.tar.gz"
    ]
    assert lines == expected_lines, f"Report content is incorrect. Expected {expected_lines}, got {lines}"

@pytest.mark.parametrize("filename, expected_status", [
    ("app1.zip", b"STATUS=production"),
    ("app2.tar.gz", b"STATUS=production"),
    ("app3.zip", b"STATUS=development"),
    ("app4.tar.gz", b"STATUS=production")
])
def test_manifest_status(filename, expected_status):
    manifest_content = read_curated_file(filename, "manifest.txt")
    lines = manifest_lines(manifest_content)
    status_line = next((line for line in lines if line.startswith(b"STATUS=")), None)
    assert status_line == expected_status, f"In {filename}, expected {expected_status}, got {status_line}"

@pytest.mark.parametrize("filename", EXPECTED_FILES)
def test_data_bin_unchanged(filename):
    original_data = get_original_data(filename)
    curated_data = read_curated_file(filename, "data.bin")
    assert original_data == curated_data, f"data.bin in {filename} was corrupted or changed."

@pytest.mark.parametrize("filename", ["app3.zip", "app4.tar.gz"])
def test_unchanged_archives_are_exact_copies(filename):
    original_path = os.path.join(ARTIFACTS_DIR, filename)
    curated_path = os.path.join(CURATED_DIR, filename)
    with open(original_path, "rb") as f:
        original = f.read()
    with open(curated_path, "rb") as f:
        curated = f.read()
    assert curated == original, f"{filename} was required to be copied completely unchanged."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
