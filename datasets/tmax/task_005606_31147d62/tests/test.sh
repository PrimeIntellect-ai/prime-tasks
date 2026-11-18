#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import hashlib
import csv

def test_process_data_script_exists():
    script_path = "/home/user/process_data.py"
    assert os.path.isfile(script_path), f"File {script_path} is missing."

def test_features_csv_exists_and_content():
    csv_path = "/home/user/features.csv"
    assert os.path.isfile(csv_path), f"File {csv_path} is missing."

    raw_logs_dir = "/home/user/raw_logs"
    assert os.path.isdir(raw_logs_dir), f"Directory {raw_logs_dir} is missing."

    expected_rows = []
    for filename in os.listdir(raw_logs_dir):
        if filename.endswith(".log"):
            filepath = os.path.join(raw_logs_dir, filename)
            with open(filepath, "r") as f:
                content = f.read()

            tokens = re.findall(r'[a-zA-Z0-9]+', content)
            tokens = [t.lower() for t in tokens]

            token_count = len(tokens)
            vocab_size = len(set(tokens))
            error_freq = tokens.count("error")

            expected_rows.append({
                "doc_id": filename,
                "token_count": str(token_count),
                "vocab_size": str(vocab_size),
                "error_freq": str(error_freq)
            })

    expected_rows.sort(key=lambda x: x["doc_id"])

    with open(csv_path, "r", newline='') as f:
        reader = csv.DictReader(f)
        actual_rows = list(reader)

    assert reader.fieldnames == ["doc_id", "token_count", "vocab_size", "error_freq"], \
        f"CSV header is incorrect. Expected ['doc_id', 'token_count', 'vocab_size', 'error_freq'], got {reader.fieldnames}"

    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows in CSV, but found {len(actual_rows)}."

    for actual, expected in zip(actual_rows, expected_rows):
        assert actual == expected, f"Row mismatch. Expected {expected}, got {actual}"

def get_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def test_manifest_tsv_exists_and_content():
    manifest_path = "/home/user/manifest.tsv"
    assert os.path.isfile(manifest_path), f"File {manifest_path} is missing."

    files_to_track = [
        "/home/user/features.csv",
        "/home/user/raw_logs/app.log",
        "/home/user/raw_logs/server1.log",
        "/home/user/raw_logs/server2.log"
    ]

    expected_manifest_lines = []
    for filepath in files_to_track:
        if os.path.exists(filepath):
            file_hash = get_sha256(filepath)
            expected_manifest_lines.append(f"{file_hash}\t{filepath}")

    expected_manifest_lines.sort(key=lambda line: line.split("\t", 1)[1])

    with open(manifest_path, "r") as f:
        actual_manifest_lines = [line.strip("\n") for line in f.readlines()]

    assert len(actual_manifest_lines) == len(expected_manifest_lines), \
        f"Manifest should contain {len(expected_manifest_lines)} lines, but has {len(actual_manifest_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_manifest_lines, expected_manifest_lines)):
        assert actual == expected, f"Manifest line {i+1} mismatch.\nExpected: '{expected}'\nGot: '{actual}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
