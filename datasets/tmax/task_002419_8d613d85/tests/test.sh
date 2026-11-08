#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import string
import subprocess
import tempfile
from datetime import datetime, timedelta

import pytest


def test_processed_jsonl():
    """
    Validates that processed.jsonl matches the expected output derived from
    transactions.csv, including the 60-second gap-filling rule and exact columns.
    """
    processed_path = "/app/processed.jsonl"
    assert os.path.exists(processed_path), f"Missing file: {processed_path}"

    csv_path = "/app/transactions.csv"
    assert os.path.exists(csv_path), f"Missing file: {csv_path}"

    expected_records = []
    last_timestamp = None

    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            tx_id = row.get("tx_id", "")
            amount = row.get("amount", "")
            description = row.get("description", "")

            ts_str = row.get("timestamp", "").strip()
            if not ts_str:
                if last_timestamp is None:
                    pass
                else:
                    last_timestamp += timedelta(seconds=60)
                    ts_str = last_timestamp.strftime("%Y-%m-%dT%H:%M:%SZ")
            else:
                try:
                    last_timestamp = datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%SZ")
                except ValueError:
                    pass

            expected_records.append({
                "tx_id": tx_id,
                "timestamp": ts_str,
                "amount": amount,
                "description": description,
            })

    actual_records = []
    with open(processed_path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                actual_records.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON on line {line_num} in {processed_path}")

    assert len(actual_records) == len(expected_records), (
        f"Expected {len(expected_records)} records, got {len(actual_records)}"
    )

    for i, (actual, expected) in enumerate(zip(actual_records, expected_records)):
        assert actual == expected, (
            f"Record mismatch at line {i + 1}. Expected {expected}, got {actual}"
        )


def test_adversarial_filter():
    """Exercise the filter on a fresh, neutrally named corpus derived from the rules."""
    filter_path = "/home/user/suspicious_filter"
    assert os.path.exists(filter_path), f"Missing executable: {filter_path}"
    assert os.path.isfile(filter_path), f"Not a regular file: {filter_path}"
    assert os.access(filter_path, os.X_OK), f"File is not executable: {filter_path}"

    def filler(length=18):
        return "".join(secrets.choice(string.ascii_lowercase) for _ in range(length))

    descriptions = [
        f"Grocery shopping {filler()}",
        f"Payment for services {filler()}",
        f"Invoice 123 {filler()}",
        f"lowercase test and demo {filler()}",
        f"CONTEST winner {filler()}",
        f"TESTING equipment {filler()}",
        f"DEMOLITION work {filler()}",
        f"MYDEMO package {filler()}",
        f"Reference 12 34 {filler()}",
        f"Reference 123-456 {filler()}",
        f"Mixed Test Demo {filler()}",
        f"Ordinary description {filler()}",
        f"System TEST run {filler()}",
        f"Product DEMO {filler()}",
        f"Review (TEST), please {filler()}",
        f"A DEMO! is scheduled {filler()}",
        f"Account {secrets.randbelow(9000) + 1000} funding {filler()}",
        f"Code x{secrets.randbelow(90000) + 10000}y {filler()}",
        f"Leading {secrets.randbelow(900000) + 100000} {filler()}",
        f"TEST {secrets.randbelow(9000) + 1000} {filler()}",
    ]

    rule = re.compile(r"\b(?:TEST|DEMO)\b|[0-9]{4,}")
    cases = [(text, 1 if rule.search(text) else 0) for text in descriptions]
    assert any(expected == 0 for _, expected in cases)
    assert any(expected == 1 for _, expected in cases)
    secrets.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="descriptions-") as corpus_dir:
        for text, expected in cases:
            path = os.path.join(corpus_dir, secrets.token_hex(16))
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)

            try:
                result = subprocess.run(
                    [filter_path, path],
                    capture_output=True,
                    timeout=5,
                )
            except subprocess.TimeoutExpired:
                failures.append(f"filter timed out for {text!r}")
                continue

            if result.returncode != expected:
                failures.append(
                    f"expected exit {expected}, got {result.returncode} for {text!r}"
                )

    if failures:
        pytest.fail(" | ".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
