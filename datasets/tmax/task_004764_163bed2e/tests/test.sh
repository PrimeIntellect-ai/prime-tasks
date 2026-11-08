#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import random
import secrets
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/sanitizer.sh"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_adversarial_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.csv"))

    assert len(clean_files) > 0, f"No clean CSV files found in {CLEAN_CORPUS_DIR}"
    assert len(evil_files) > 0, f"No evil CSV files found in {EVIL_CORPUS_DIR}"

    clean_failed = []
    evil_failed = []

    for clean_file in clean_files:
        try:
            result = subprocess.run([SCRIPT_PATH, clean_file], capture_output=True, text=True, timeout=5)
            output = result.stdout.strip()
            if output != "ACCEPT":
                clean_failed.append((os.path.basename(clean_file), output))
        except Exception as e:
            clean_failed.append((os.path.basename(clean_file), str(e)))

    for evil_file in evil_files:
        try:
            result = subprocess.run([SCRIPT_PATH, evil_file], capture_output=True, text=True, timeout=5)
            output = result.stdout.strip()
            if output != "REJECT":
                evil_failed.append((os.path.basename(evil_file), output))
        except Exception as e:
            evil_failed.append((os.path.basename(evil_file), str(e)))

    error_messages = []
    if clean_failed:
        failed_names = [f[0] for f in clean_failed]
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(failed_names)}")

    if evil_failed:
        failed_names = [f[0] for f in evil_failed]
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed/accepted. Offending files: {', '.join(failed_names)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def mixed_case(value):
    return "".join(ch.upper() if secrets.randbits(1) else ch.lower() for ch in value)


def safe_query():
    suffix = secrets.token_hex(6)
    return f'SELECT id, name FROM customer_data_{suffix} WHERE status = "active";'


def write_batch(path, queries):
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["query_id", "query_text"])
        for index, query in enumerate(queries, 1):
            writer.writerow([index, query])


def test_generated_hidden_batches_from_neutral_paths():
    cases = []
    bad_queries = [
        lambda: f"SELECT * FROM {mixed_case('sys_config')};",
        lambda: f"SELECT token FROM {mixed_case('user_passwords')} WHERE id = 7;",
        lambda: f"SELECT {mixed_case('pg_sleep')}(2);",
        lambda: f"SELECT {mixed_case('dbms_lock.sleep')}(2);",
        lambda: f"SELECT p.id FROM products p JOIN {mixed_case('sys_config')} s ON p.id = s.id;",
        lambda: f"SELECT id FROM accounts WHERE check_value = {mixed_case('pg_sleep')}(1);",
    ]

    with tempfile.TemporaryDirectory(prefix="batch-check-") as directory:
        # Randomly generated safe batches exercise arbitrary paths, multiple rows,
        # mixed SQL casing, and correctly quoted query_text fields containing commas.
        for _ in range(12):
            queries = [safe_query() for _ in range(random.randint(1, 5))]
            queries.append(f"SeLeCt id, name FROM ordinary_{secrets.token_hex(5)};")
            random.shuffle(queries)
            path = os.path.join(directory, f"{uuid.uuid4().hex}.csv")
            write_batch(path, queries)
            cases.append((path, "ACCEPT"))

        # Each malicious batch is independently generated and places the unsafe
        # query among a random number of safe rows, with randomized keyword casing.
        for factory in bad_queries:
            for _ in range(2):
                queries = [safe_query() for _ in range(random.randint(1, 4))]
                queries.insert(random.randrange(len(queries) + 1), factory())
                path = os.path.join(directory, f"{uuid.uuid4().hex}.csv")
                write_batch(path, queries)
                cases.append((path, "REJECT"))

        random.SystemRandom().shuffle(cases)
        failures = []
        for path, expected in cases:
            try:
                result = subprocess.run(
                    [SCRIPT_PATH, path], capture_output=True, text=True, timeout=5
                )
                actual = result.stdout.strip()
                if actual != expected:
                    failures.append((os.path.basename(path), expected, actual))
            except Exception as exc:
                failures.append((os.path.basename(path), expected, str(exc)))

        assert not failures, "Generated batch failures: " + repr(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
