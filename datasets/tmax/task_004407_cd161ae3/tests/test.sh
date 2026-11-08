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

SCRIPT_PATH = "/home/user/filter_backup.sh"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"
SENSITIVE_TABLE = "omega_vault_credentials"

def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing: {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script is not executable: {SCRIPT_PATH}"

def test_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.sql"))
    assert len(clean_files) > 0, "No clean files found."

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run([SCRIPT_PATH, filepath], capture_output=True, text=True)
        stdout = result.stdout.strip()
        if result.returncode != 0 or stdout != "CLEAN":
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected (should be accepted). Offending files: {', '.join(failed_files)}")

def test_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.sql"))
    assert len(evil_files) > 0, "No evil files found."

    failed_files = []
    for filepath in evil_files:
        result = subprocess.run([SCRIPT_PATH, filepath], capture_output=True, text=True)
        stdout = result.stdout.strip()
        if result.returncode != 1 or stdout != "EVIL":
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed (should be rejected). Offending files: {', '.join(failed_files)}")

def test_path_independent_hidden_queries():
    token = secrets.token_hex(6)
    safe_table = f"backup_metrics_{token}"
    safe_join = f"account_profiles_{token}"
    column = f"metric_{token}"

    cases = [
        (f"SELECT {column} FROM {safe_table} WHERE {column} > 10;\n", 0, "CLEAN"),
        (f"SELECT a.id FROM {safe_table} a JOIN {safe_join} b ON a.id = b.id;\n", 0, "CLEAN"),
        (f"WITH recent AS (SELECT id FROM {safe_table}) SELECT id FROM recent;\n", 0, "CLEAN"),
        (f"SELECT * FROM (SELECT {column} FROM {safe_table}) AS q;\n", 0, "CLEAN"),
        (f"SELECT * FROM {SENSITIVE_TABLE};\n", 1, "EVIL"),
        (f'SELECT u.id FROM users u JOIN "{SENSITIVE_TABLE}" v ON u.id = v.user_id;\n', 1, "EVIL"),
        (f"SELECT * FROM (SELECT user_id FROM `{SENSITIVE_TABLE}`) AS stolen;\n", 1, "EVIL"),
        (f"WITH exposed AS (SELECT password_hash FROM {SENSITIVE_TABLE}) SELECT * FROM exposed;\n", 1, "EVIL"),
    ]

    random.SystemRandom().shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="sql_eval_") as temp_dir:
        failures = []
        for sql, expected_code, expected_stdout in cases:
            filepath = os.path.join(temp_dir, secrets.token_hex(12) + ".sql")
            with open(filepath, "w", encoding="utf-8") as handle:
                handle.write(sql)

            result = subprocess.run(
                [SCRIPT_PATH, filepath], capture_output=True, text=True, timeout=10
            )
            if result.returncode != expected_code or result.stdout.strip() != expected_stdout:
                failures.append(
                    f"{os.path.basename(filepath)} expected {expected_stdout}/{expected_code}, "
                    f"got {result.stdout.strip()!r}/{result.returncode}"
                )

        if failures:
            pytest.fail("Path-independent query checks failed: " + "; ".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
