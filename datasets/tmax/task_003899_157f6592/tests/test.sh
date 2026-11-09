#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import string
import subprocess

BINARY = '/home/user/query_sanitizer'
SOURCE = '/home/user/query_sanitizer.c'


def run_binary(input_text):
    return subprocess.run(
        [BINARY],
        input=input_text,
        text=True,
        capture_output=True,
        timeout=10,
    )


def test_done_file():
    done_file = '/home/user/done.txt'
    assert os.path.isfile(done_file), f"Expected file {done_file} does not exist."
    with open(done_file, 'r') as f:
        content = f.read().strip()
    assert content == "READY", f"Expected {done_file} to contain 'READY', but found '{content}'."


def test_binary_exists_and_executable():
    assert os.path.isfile(BINARY), f"Expected binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."
    assert os.path.isfile(SOURCE), f"Expected C source {SOURCE} does not exist."
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"Expected {BINARY} to be a compiled ELF binary."


def test_adversarial_corpus():
    evil_corpus_path = '/app/verifier/corpus/evil.txt'
    clean_corpus_path = '/app/verifier/corpus/clean.txt'

    assert os.path.isfile(evil_corpus_path), f"Evil corpus {evil_corpus_path} missing."
    assert os.path.isfile(clean_corpus_path), f"Clean corpus {clean_corpus_path} missing."

    with open(evil_corpus_path, 'r') as f:
        evil_queries = f.read().splitlines()

    evil_bypassed = []
    for query in evil_queries:
        if not query.strip():
            continue
        proc = run_binary(query + '\n')
        output = proc.stdout.strip()
        if proc.returncode != 0 or output != "MALICIOUS":
            evil_bypassed.append(query)

    with open(clean_corpus_path, 'r') as f:
        clean_queries = f.read().splitlines()

    clean_modified = []
    for query in clean_queries:
        if not query.strip():
            continue
        proc = run_binary(query + '\n')
        output = proc.stdout.strip()
        if proc.returncode != 0 or output != "SAFE":
            clean_modified.append(query)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_queries)} evil bypassed. Offending queries: {evil_bypassed[:5]}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_queries)} clean modified (flagged as malicious). Offending queries: {clean_modified[:5]}")

    assert not evil_bypassed and not clean_modified, " | ".join(error_msgs)


def token(prefix='x'):
    alphabet = string.ascii_letters + string.digits
    return prefix + ''.join(secrets.choice(alphabet) for _ in range(12))


def test_generated_queries_and_stream_processing():
    cases = []

    for _ in range(24):
        table = token('tbl_')
        column = token('col_')
        prefix = f"/* {token('audit_')} */ "
        suffix = f" RETURN {token('result_')};"
        cases.append((prefix + "MATCH (n) DETACH DELETE n" + suffix, "MALICIOUS"))
        cases.append((
            f"SELECT {column}, ROW_NUMBER() OVER (PARTITION BY 1=1) FROM {table} WHERE {column} IS NOT NULL;",
            "MALICIOUS",
        ))

        label = token('Backup_')
        prop = token('date_')
        offset = secrets.randbelow(500) + 1
        limit = secrets.randbelow(100) + 1
        cases.append((
            f"MATCH (n:{label}) RETURN n ORDER BY n.{prop} DESC SKIP {offset} LIMIT {limit};",
            "SAFE",
        ))

        partition = token('account_')
        metric = token('amount_')
        cases.append((
            f"SELECT {metric}, SUM({metric}) OVER (PARTITION BY {partition}) FROM {table};",
            "SAFE",
        ))

        variable = token('v_')
        predicate = token('property_')
        cases.append((
            f"PREFIX ex: <http://example.invalid/{token('ns_')}/> SELECT ?{variable} WHERE {{ ?{variable} ex:{predicate} ?value }}",
            "SAFE",
        ))

        # Near misses ensure broad keyword blocking is not accepted.
        node = token('node_')
        cases.append((f"MATCH ({node}) DETACH DELETE {node};", "SAFE"))
        cases.append((f"SELECT COUNT(*) OVER (PARTITION BY 1) FROM {table};", "SAFE"))

    random.SystemRandom().shuffle(cases)
    input_text = ''.join(query + '\n' for query, _ in cases)
    expected = [label for _, label in cases]

    proc = run_binary(input_text)
    assert proc.returncode == 0, f"Sanitizer exited with status {proc.returncode}: {proc.stderr[:500]}"
    actual = proc.stdout.splitlines()
    assert actual == expected, (
        f"Expected exactly one correct label per input line. "
        f"Expected {len(expected)} labels, got {len(actual)}. "
        f"First mismatch: {next(((i, e, actual[i] if i < len(actual) else '<missing>') for i, e in enumerate(expected) if i >= len(actual) or actual[i] != e), 'extra output')}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
