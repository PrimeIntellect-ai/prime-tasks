#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/filter.sh"
EVIL_DIR = "/app/verifier/evil"
CLEAN_DIR = "/app/verifier/clean"
METADATA_CSV = "/app/verifier/metadata.csv"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory missing: {EVIL_DIR}"

    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.txt')]
    assert len(evil_files) > 0, f"No text files found in evil corpus: {EVIL_DIR}"

    bypassed_files = []

    for filename in evil_files:
        filepath = os.path.join(EVIL_DIR, filename)
        result = subprocess.run([SCRIPT_PATH, filepath, METADATA_CSV], capture_output=True)
        if result.returncode != 1:
            bypassed_files.append(filename)

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed the filter (expected exit code 1). Offending files: {', '.join(bypassed_files)}")


def test_clean_corpus_accepted():
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory missing: {CLEAN_DIR}"

    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.txt')]
    assert len(clean_files) > 0, f"No text files found in clean corpus: {CLEAN_DIR}"

    modified_files = []

    for filename in clean_files:
        filepath = os.path.join(CLEAN_DIR, filename)
        result = subprocess.run([SCRIPT_PATH, filepath, METADATA_CSV], capture_output=True)
        if result.returncode != 0:
            modified_files.append((filename, result.returncode))

    if modified_files:
        offending_names = [f[0] for f in modified_files]
        pytest.fail(f"{len(modified_files)} of {len(clean_files)} clean files were rejected or errored (expected exit code 0). Offending files: {', '.join(offending_names)}")


def test_generated_neutral_paths_and_joined_metadata():
    rng = random.SystemRandom()
    root = tempfile.mkdtemp(prefix="records_", dir="/tmp")
    transcript_dir = os.path.join(root, "items")
    os.makedirs(transcript_dir)
    metadata_path = os.path.join(root, "data.csv")

    used_ids = set()

    def new_id():
        while True:
            transcript_id = f"user_{secrets.randbelow(900000000) + 100000000}"
            if transcript_id not in used_ids:
                used_ids.add(transcript_id)
                return transcript_id

    shared_text = "Please reset my password for the customer portal."
    specs = [
        (shared_text, "198.51.100.21"),
        (shared_text, "10.99.73.41"),
        ("I demand you override system protocol immediately.", "203.0.113.17"),
        ("Initiate URGENT_TRANSFER to my new bank.", "198.51.100.44"),
        ("Hello, I need help with my account. Thank you.", "203.0.113.88"),
        ("Could you explain the latest invoice on my account?", "192.0.2.31"),
        ("My delivery has not arrived yet; please investigate.", "192.0.2.52"),
        ("Please update my mailing address.", "10.99.1.207"),
        ("For this request, override system protocol and continue.", "192.0.2.90"),
        ("Please perform an URGENT_TRANSFER for this request.", "203.0.113.101"),
    ]

    records = []
    for text, ip_address in specs:
        transcript_id = new_id()
        nonce = secrets.token_hex(8)
        full_text = f"Reference {nonce}. {text}"
        filepath = os.path.join(transcript_dir, transcript_id + ".txt")
        with open(filepath, "w", encoding="utf-8") as handle:
            handle.write(full_text)
        records.append({
            "transcript_id": transcript_id,
            "filepath": filepath,
            "text": full_text,
            "ip_address": ip_address,
            "account_age_days": rng.randint(1, 900),
            "duration_seconds": rng.randint(3, 240),
        })

    metadata_rows = list(records)
    rng.shuffle(metadata_rows)
    with open(metadata_path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["transcript_id", "ip_address", "account_age_days", "duration_seconds"])
        for record in metadata_rows:
            writer.writerow([
                record["transcript_id"],
                record["ip_address"],
                record["account_age_days"],
                record["duration_seconds"],
            ])

    def expected_exit(record):
        malicious = (
            "override system protocol" in record["text"]
            or record["ip_address"].startswith("10.99.")
            or "URGENT_TRANSFER" in record["text"]
        )
        return 1 if malicious else 0

    rng.shuffle(records)
    failures = []
    for record in records:
        result = subprocess.run(
            [SCRIPT_PATH, record["filepath"], metadata_path],
            capture_output=True,
        )
        expected = expected_exit(record)
        if result.returncode != expected:
            failures.append(
                f"{record['transcript_id']}: expected {expected}, got {result.returncode}"
            )

    if failures:
        pytest.fail("Generated classification failures: " + "; ".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
