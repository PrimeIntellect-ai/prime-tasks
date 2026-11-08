#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess
import tempfile

VALIDATOR_SCRIPT = "/home/user/query_validator.py"
EVIL_CORPUS_DIR = "/app/eval_corpus/evil"
CLEAN_CORPUS_DIR = "/app/eval_corpus/clean"


def run_validator(filepath, timeout=5):
    result = subprocess.run(
        ["python3", VALIDATOR_SCRIPT, filepath],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return result.stdout.strip(), result.stderr.strip()


def run_validator_strict(filepath):
    result = subprocess.run(
        ["python3", VALIDATOR_SCRIPT, filepath],
        capture_output=True,
        text=True,
        timeout=5,
    )
    return result


def test_validator_script_exists():
    assert os.path.isfile(VALIDATOR_SCRIPT), f"Validator script missing at {VALIDATOR_SCRIPT}"


def test_adversarial_corpus():
    assert os.path.isfile(VALIDATOR_SCRIPT), "Validator script missing."

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.sql')]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.sql')]

    bypassed_evil = []
    rejected_clean = []

    for evil_file in evil_files:
        stdout, _ = run_validator(evil_file)
        if stdout != "REJECT":
            bypassed_evil.append(os.path.basename(evil_file))

    for clean_file in clean_files:
        stdout, _ = run_validator(clean_file)
        if stdout != "ACCEPT":
            rejected_clean.append(os.path.basename(clean_file))

    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if rejected_clean:
        errors.append(f"{len(rejected_clean)} of {len(clean_files)} clean rejected: {', '.join(rejected_clean)}")

    assert not errors, " | ".join(errors)


def randomized_case(sql, rng):
    words = [
        "transactions", "created_at", "row_number", "partition", "update",
        "orders", "users", "select", "where", "begin", "commit", "rank",
        "window", "order", "over", "from", "set", "with", "join", "and",
        "by", "as", "is", "not", "null"
    ]
    pattern = re.compile(r"\b(" + "|".join(sorted(words, key=len, reverse=True)) + r")\b", re.I)

    def alter(match):
        return "".join(c.upper() if rng.randrange(2) else c.lower() for c in match.group(0))

    return pattern.sub(alter, sql)


def test_fresh_hidden_queries():
    assert os.path.isfile(VALIDATOR_SCRIPT), "Validator script missing."

    rng = random.SystemRandom()
    tag = secrets.token_hex(8)
    n = rng.randrange(101, 900000)
    date = f"20{rng.randrange(20, 26):02d}-{rng.randrange(1, 13):02d}-{rng.randrange(1, 28):02d}"
    other = f"metrics_{tag}"

    cases = [
        ("ACCEPT", f"SELECT * FROM unrelated_{tag};"),
        ("ACCEPT", f"UPDATE transactions SET amount = {n};"),
        ("ACCEPT", f"BEGIN; UPDATE orders SET status = {n}; UPDATE users SET status = {n + 1}; COMMIT;"),
        ("ACCEPT", f"BEGIN; UPDATE users SET status = {n}; COMMIT; BEGIN; UPDATE orders SET status = {n + 1}; COMMIT;"),
        ("ACCEPT", f"SELECT id, RANK() OVER (PARTITION BY region ORDER BY score DESC) AS r FROM {other};"),
        ("ACCEPT", f"SELECT id, ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY id) AS rn FROM {other};"),
        ("ACCEPT", f"SELECT * FROM transactions WHERE created_at >= '{date}' AND amount > {n};"),
        ("ACCEPT", f"SELECT t.id FROM transactions AS t WHERE t.created_at IS NOT NULL;"),
        ("ACCEPT", f"WITH recent AS (SELECT * FROM transactions WHERE created_at > '{date}') SELECT * FROM recent;"),
        ("ACCEPT", f"SELECT 'UPDATE users; UPDATE orders', 'RANK() OVER (ORDER BY id)' FROM notes_{tag};"),
        ("REJECT", f"BEGIN; UPDATE users SET status = {n}; UPDATE orders SET status = {n + 1}; COMMIT;"),
        ("REJECT", f"BEGIN; UPDATE orders SET status = {n}; UPDATE users SET status = {n + 1}; UPDATE orders SET status = {n + 2}; COMMIT;"),
        ("REJECT", f"SELECT id, RANK() OVER (ORDER BY score DESC) AS r FROM {other};"),
        ("REJECT", f"SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM {other};"),
        ("REJECT", f"SELECT * FROM transactions;"),
        ("REJECT", f"SELECT * FROM transactions WHERE amount > {n};"),
        ("REJECT", f"WITH recent AS (SELECT * FROM transactions WHERE amount > {n}) SELECT * FROM recent;"),
        ("REJECT", f"SELECT id, RANK() OVER (PARTITION BY region ORDER BY score), ROW_NUMBER() OVER (ORDER BY id) FROM {other};"),
        ("REJECT", f"SELECT ROW_NUMBER() OVER (ORDER BY id) FROM transactions WHERE created_at > '{date}';"),
        ("REJECT", f"SELECT RANK() OVER (PARTITION BY region ORDER BY amount) FROM transactions WHERE amount > {n};"),
    ]
    rng.shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix=f"validator_hidden_{tag}_") as directory:
        for expected, sql in cases:
            nonce = secrets.token_hex(12)
            sql = f"/* request {nonce} */\n" + randomized_case(sql, rng) + f"\n/* end {nonce[::-1]} */\n"
            path = os.path.join(directory, f"{secrets.token_hex(16)}.sql")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(sql)

            try:
                result = run_validator_strict(path)
            except subprocess.TimeoutExpired:
                failures.append(f"{os.path.basename(path)} timed out; expected {expected}")
                continue

            valid_stdout = result.stdout == expected or result.stdout == expected + "\n"
            if result.returncode != 0 or not valid_stdout:
                failures.append(
                    f"{os.path.basename(path)} expected {expected}, got return code "
                    f"{result.returncode} and stdout {result.stdout!r}"
                )

    assert not failures, " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
