#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import glob
import random
import secrets
import subprocess
import tempfile
import pytest

EVIL_DIR = "/app/corpora/evil"
CLEAN_DIR = "/app/corpora/clean"
SCRIPT_PATH = "/home/user/graph_sanitizer.py"

def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"

def test_evil_corpus_rejected():
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.csv"))
    assert len(evil_files) > 0, f"No evil files found in {EVIL_DIR}"

    bypassed = []
    for filepath in evil_files:
        result = subprocess.run(
            ["python3", SCRIPT_PATH, filepath],
            capture_output=True,
            text=True
        )
        stdout = result.stdout.strip()
        if result.returncode != 1 or stdout != "REJECT":
            bypassed.append(os.path.basename(filepath))

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {bypassed}")

def test_clean_corpus_accepted():
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.csv"))
    assert len(clean_files) > 0, f"No clean files found in {CLEAN_DIR}"

    rejected = []
    for filepath in clean_files:
        result = subprocess.run(
            ["python3", SCRIPT_PATH, filepath],
            capture_output=True,
            text=True
        )
        stdout = result.stdout.strip()
        if result.returncode != 0 or stdout != "ACCEPT":
            rejected.append(os.path.basename(filepath))

    if rejected:
        pytest.fail(f"{len(rejected)} of {len(clean_files)} clean modified/rejected: {rejected}")

def oracle_expected(rows):
    for src, dst, transaction_type, amount in rows:
        if src == dst or len(transaction_type) > 12 or ";" in transaction_type:
            return 1, "REJECT"
    return 0, "ACCEPT"

def make_rows(case_kind, nonce):
    rows = [
        (f"acct_{nonce}_a", f"acct_{nonce}_b", "TRANSFER", "100"),
        (f"acct_{nonce}_b", f"acct_{nonce}_c", "DEPOSIT", "50"),
        (f"acct_{nonce}_c", f"acct_{nonce}_d", "PAYMENT", "25"),
    ]
    position = secrets.randbelow(len(rows))
    src, dst, transaction_type, amount = rows[position]
    if case_kind == "self_loop":
        rows[position] = (src, src, transaction_type, amount)
    elif case_kind == "long_type":
        rows[position] = (src, dst, "X" * (13 + secrets.randbelow(20)), amount)
    elif case_kind == "semicolon":
        rows[position] = (src, dst, "PAY;LOAD", amount)
    elif case_kind != "safe":
        raise AssertionError(f"unknown generated case: {case_kind}")
    return rows

def test_generated_path_independent_cases():
    # Reuse one unpredictable, neutrally named path while changing its contents.
    # This ensures the result must come from the CSV data rather than directory or
    # filename labels.
    case_kinds = ["safe", "self_loop", "long_type", "semicolon"] * 12
    random.SystemRandom().shuffle(case_kinds)

    with tempfile.TemporaryDirectory(prefix="gs_" + secrets.token_hex(8) + "_") as temp_dir:
        filepath = os.path.join(temp_dir, secrets.token_hex(12) + ".csv")
        failures = []
        for index, case_kind in enumerate(case_kinds):
            nonce = secrets.token_hex(10)
            rows = make_rows(case_kind, nonce)
            expected_code, expected_stdout = oracle_expected(rows)
            with open(filepath, "w", encoding="utf-8", newline="") as f:
                for row in rows:
                    f.write(",".join(row) + "\n")

            try:
                result = subprocess.run(
                    ["python3", SCRIPT_PATH, filepath],
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
            except subprocess.TimeoutExpired:
                failures.append(f"case {index} timed out")
                continue

            if result.returncode != expected_code or result.stdout.strip() != expected_stdout:
                failures.append(
                    f"case {index}: expected ({expected_code}, {expected_stdout}), "
                    f"got ({result.returncode}, {result.stdout.strip()!r})"
                )

        if failures:
            pytest.fail("Generated CSV checks failed: " + "; ".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
