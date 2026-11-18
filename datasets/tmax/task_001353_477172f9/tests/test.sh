#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest

VALIDATOR_PATH = "/home/user/validator"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def run_validator(filepath):
    return subprocess.run(
        [VALIDATOR_PATH, filepath],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_validator_exists_and_executable():
    assert os.path.isfile(VALIDATOR_PATH), f"Validator binary not found at {VALIDATOR_PATH}"
    assert os.access(VALIDATOR_PATH, os.X_OK), f"Validator binary at {VALIDATOR_PATH} is not executable"


def test_clean_corpus():
    if not os.path.isdir(CLEAN_CORPUS_DIR):
        pytest.fail(f"Clean corpus directory missing at {CLEAN_CORPUS_DIR}")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.sql')]
    if not clean_files:
        pytest.fail("No SQL files found in clean corpus.")

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        result = run_validator(filepath)
        if result.returncode != 0:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean queries rejected (expected to pass): {', '.join(failed_files)}")


def test_evil_corpus():
    if not os.path.isdir(EVIL_CORPUS_DIR):
        pytest.fail(f"Evil corpus directory missing at {EVIL_CORPUS_DIR}")

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.sql')]
    if not evil_files:
        pytest.fail("No SQL files found in evil corpus.")

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        result = run_validator(filepath)
        if result.returncode == 0:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil queries bypassed (expected to fail): {', '.join(failed_files)}")


def test_generated_queries_at_neutral_paths():
    rng = random.SystemRandom()
    cases = []

    # Derive each expected result from independently selected rule violations,
    # then construct the corresponding SQL with randomized aliases and values.
    for implicit_cross_join in (False, True):
        for hardcoded_tenant in (False, True):
            for _ in range(4):
                tx_alias = "t" + secrets.token_hex(3)
                emp_alias = "e" + secrets.token_hex(3)

                if implicit_cross_join:
                    from_clause = f"transactions {tx_alias}, employees {emp_alias}"
                    relationship = f"{tx_alias}.employee_id = {emp_alias}.id AND "
                else:
                    from_clause = (
                        f"transactions {tx_alias} JOIN employees {emp_alias} "
                        f"ON {tx_alias}.employee_id = {emp_alias}.id"
                    )
                    relationship = ""

                tenant_value = str(rng.randint(2, 1000000)) if hardcoded_tenant else rng.choice(["?", "$1"])
                sql = (
                    f"SELECT {tx_alias}.amount\n"
                    f"FROM {from_clause}\n"
                    f"WHERE {relationship}{tx_alias}.tenant_id = {tenant_value} "
                    f"AND {emp_alias}.active = true;\n"
                )
                expected_clean = not (implicit_cross_join or hardcoded_tenant)
                cases.append((sql, expected_clean))

    # Exercise the single-table tenant rule as well.
    for _ in range(4):
        alias = "n" + secrets.token_hex(3)
        hardcoded_tenant = rng.choice([False, True])
        tenant_value = str(rng.randint(2, 1000000)) if hardcoded_tenant else rng.choice(["?", "$1"])
        sql = f"SELECT {alias}.id FROM nodes {alias} WHERE {alias}.tenant_id = {tenant_value};\n"
        cases.append((sql, not hardcoded_tenant))

    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="sql-audit-") as temp_dir:
        failures = []
        for sql, expected_clean in cases:
            filepath = os.path.join(temp_dir, secrets.token_hex(12) + ".sql")
            with open(filepath, "w", encoding="utf-8") as query_file:
                query_file.write(sql)

            result = run_validator(filepath)
            actual_clean = result.returncode == 0
            if actual_clean != expected_clean:
                failures.append(
                    f"expected {'clean' if expected_clean else 'evil'}, got exit {result.returncode}: {sql!r}"
                )

        if failures:
            pytest.fail("Generated neutral-path validation failures:\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
