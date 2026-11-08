#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import hashlib

BASE_DIR = "/home/user/datasets"
PROCESSED_DIR = os.path.join(BASE_DIR, "processed")
ALIASES_DIR = os.path.join(BASE_DIR, "aliases")
METADATA_PATH = os.path.join(BASE_DIR, "metadata.json")
MANIFEST_PATH = os.path.join(BASE_DIR, "manifest.txt")

EXPECTED_DATASETS = [
    {
        "source": "/home/user/datasets/raw/data1.csv",
        "original_encoding": "iso-8859-1",
        "alias": "clinical_trials_2023.csv",
    },
    {
        "source": "/home/user/datasets/raw/data2.json",
        "original_encoding": "utf-16le",
        "alias": "patient_records.json",
    },
]


def load_metadata():
    assert os.path.isfile(METADATA_PATH), f"Metadata file missing: {METADATA_PATH}"
    with open(METADATA_PATH, "r", encoding="utf-8") as f:
        metadata = json.load(f)
    assert metadata.get("datasets") == EXPECTED_DATASETS, (
        "metadata.json must retain the original two dataset entries"
    )
    return metadata


def test_directories_created():
    assert os.path.isdir(PROCESSED_DIR), f"Directory not found: {PROCESSED_DIR}"
    assert os.path.isdir(ALIASES_DIR), f"Directory not found: {ALIASES_DIR}"


def test_metadata_preserved():
    load_metadata()


def test_processed_files_utf8():
    metadata = load_metadata()

    for ds in metadata.get("datasets", []):
        source_path = ds["source"]
        original_encoding = ds["original_encoding"]
        filename = os.path.basename(source_path)
        processed_path = os.path.join(PROCESSED_DIR, filename)

        assert os.path.isfile(processed_path), f"Processed file missing: {processed_path}"

        # Read original to get expected content
        with open(source_path, "r", encoding=original_encoding) as f:
            expected_content = f.read()

        # Read processed as UTF-8
        try:
            with open(processed_path, "r", encoding="utf-8") as f:
                actual_content = f.read()
        except UnicodeDecodeError:
            assert False, f"Processed file {processed_path} is not valid UTF-8"

        assert actual_content == expected_content, f"Content mismatch in {processed_path}"


def test_symlinks_created():
    metadata = load_metadata()

    for ds in metadata.get("datasets", []):
        alias = ds["alias"]
        filename = os.path.basename(ds["source"])
        alias_path = os.path.join(ALIASES_DIR, alias)
        expected_target = os.path.join(PROCESSED_DIR, filename)

        assert os.path.islink(alias_path), f"Symlink missing or not a link: {alias_path}"

        actual_target = os.readlink(alias_path)
        # Handle relative or absolute symlinks
        if not os.path.isabs(actual_target):
            actual_target = os.path.normpath(os.path.join(ALIASES_DIR, actual_target))

        assert actual_target == expected_target, f"Symlink {alias_path} points to {actual_target}, expected {expected_target}"


def test_manifest_file():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing: {MANIFEST_PATH}"
    metadata = load_metadata()

    expected_lines = []
    for ds in metadata.get("datasets", []):
        source_path = ds["source"]
        original_encoding = ds["original_encoding"]
        filename = os.path.basename(source_path)

        with open(source_path, "r", encoding=original_encoding) as f:
            content = f.read()

        file_hash = hashlib.sha256(content.encode("utf-8")).hexdigest()
        expected_lines.append(f"{file_hash}  {filename}")

    expected_lines.sort()

    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, "Manifest file contents or sorting are incorrect"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
