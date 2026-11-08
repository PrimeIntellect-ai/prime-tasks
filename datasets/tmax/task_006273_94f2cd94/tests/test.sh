#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import hashlib
import configparser

BASE_DIR = "/home/user"
RAW_DIR = os.path.join(BASE_DIR, "raw_docs")
OUTPUT_DIR = os.path.join(BASE_DIR, "organized_docs")
MANIFEST_PATH = os.path.join(OUTPUT_DIR, "manifest.csv")
METADATA_PATH = os.path.join(RAW_DIR, "metadata.json")
RULES_PATH = os.path.join(BASE_DIR, "doc_rules.ini")


def sha1_file(path):
    digest = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def expected_entries():
    with open(METADATA_PATH, "r", encoding="utf-8") as f:
        metadata = json.load(f)

    config = configparser.ConfigParser()
    assert config.read(RULES_PATH), f"Could not read rules file at {RULES_PATH}"

    rules_by_magic = {}
    for section in config.sections():
        magic = config[section]["magic"].upper()
        rules_by_magic[magic] = {
            "directory": config[section]["directory"],
            "extension": config[section]["extension"],
        }

    entries = []
    for root, dirs, files in os.walk(RAW_DIR):
        dirs.sort()
        files.sort()
        for filename in files:
            source_path = os.path.join(root, filename)
            if os.path.abspath(source_path) == os.path.abspath(METADATA_PATH):
                continue

            source_sha1 = sha1_file(source_path)
            assert source_sha1 in metadata, f"Source file hash is absent from metadata.json: {source_path}"
            title = metadata[source_sha1]["title"]

            with open(source_path, "rb") as f:
                signature = f.read(4).hex().upper()
            assert signature in rules_by_magic, f"No rule for signature {signature} from {source_path}"

            rule = rules_by_magic[signature]
            relative_path = os.path.join(
                rule["directory"], f"{title}.{rule['extension']}"
            ).replace(os.sep, "/")
            entries.append((title, relative_path, source_sha1, source_path))

    entries.sort(key=lambda entry: entry[0])
    return entries


def read_manifest():
    with open(MANIFEST_PATH, "r", newline="", encoding="utf-8") as f:
        return list(csv.reader(f))


def test_organized_docs_directory_exists():
    assert os.path.isdir(OUTPUT_DIR), "/home/user/organized_docs directory is missing"


def test_manifest_exists_and_format():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing at {MANIFEST_PATH}"

    rows = read_manifest()
    assert len(rows) > 0, "manifest.csv is empty"

    headers = rows[0]
    expected_headers = ["Title", "RelativePath", "SHA1"]
    assert headers == expected_headers, f"manifest.csv headers are incorrect. Expected {expected_headers}, got {headers}"

    data_rows = rows[1:]
    assert len(data_rows) == 4, f"Expected exactly 4 data rows in manifest.csv, found {len(data_rows)}"
    assert all(len(row) == 3 for row in data_rows), "Every manifest data row must have exactly 3 columns"

    titles = [row[0] for row in data_rows]
    assert titles == sorted(titles), "manifest.csv is not sorted alphabetically by the Title column"


def test_organized_files_exist_and_match_manifest():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing at {MANIFEST_PATH}"

    rows = read_manifest()[1:]
    for title, rel_path, expected_sha1 in rows:
        abs_path = os.path.join(OUTPUT_DIR, rel_path)
        assert os.path.isfile(abs_path), f"File specified in manifest is missing from disk: {abs_path}"

        actual_sha1 = sha1_file(abs_path)
        assert actual_sha1 == expected_sha1, f"SHA1 hash mismatch for {abs_path}. Manifest says {expected_sha1}, but file is {actual_sha1}"


def test_manifest_and_copies_match_sources_metadata_and_rules():
    expected = expected_entries()
    assert len(expected) == 4, f"Expected to process exactly 4 source files, found {len(expected)}"

    actual_rows = read_manifest()[1:]
    expected_rows = [[title, rel_path, source_sha1] for title, rel_path, source_sha1, _ in expected]
    assert actual_rows == expected_rows, (
        "manifest.csv does not exactly match the titles, target paths, and SHA-1 hashes "
        "derived from all raw source files, metadata.json, and doc_rules.ini"
    )

    for title, rel_path, source_sha1, source_path in expected:
        output_path = os.path.join(OUTPUT_DIR, *rel_path.split("/"))
        assert os.path.isfile(output_path), f"Expected organized copy is missing: {output_path}"
        assert sha1_file(output_path) == source_sha1, f"Organized file is not an exact copy of {source_path}: {output_path}"
        with open(source_path, "rb") as source, open(output_path, "rb") as output:
            assert source.read() == output.read(), f"Organized file content differs from source: {output_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
