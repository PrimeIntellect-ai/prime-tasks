#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import os
import random
import secrets
import subprocess
import tempfile
import pytest

EXECUTABLE = "/home/user/query_filter"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"
MAX_DEPTH = 4
ALLOWED_SCHEMA = {
    ("Customer", "PURCHASED", "Product"),
    ("Product", "MANUFACTURED_BY", "Company"),
    ("Customer", "KNOWS", "Customer"),
}


def run_filter(filepath):
    return subprocess.run(
        [EXECUTABLE, filepath],
        capture_output=True,
        timeout=5,
    )


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"


def test_clean_corpus_accepted():
    assert os.path.isdir(CLEAN_CORPUS), f"Clean corpus directory missing at {CLEAN_CORPUS}"
    clean_files = [f for f in os.listdir(CLEAN_CORPUS) if f.endswith('.cql')]
    assert len(clean_files) > 0, "No clean corpus files found"

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS, filename)
        result = run_filter(filepath)
        if result.returncode != 0:
            failed_files.append(filename)

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(failed_files)}"


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_CORPUS), f"Evil corpus directory missing at {EVIL_CORPUS}"
    evil_files = [f for f in os.listdir(EVIL_CORPUS) if f.endswith('.cql')]
    assert len(evil_files) > 0, "No evil corpus files found"

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS, filename)
        result = run_filter(filepath)
        if result.returncode == 0:
            failed_files.append(filename)

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(failed_files)}"


def test_generated_queries_are_classified_by_content():
    labels = ["Customer", "Product", "Company"]
    relationships = ["PURCHASED", "MANUFACTURED_BY", "KNOWS"]
    cases = []

    # Exercise every combination of the documented labels and relationship types.
    triples = list(itertools.product(labels, relationships, labels))
    random.SystemRandom().shuffle(triples)
    for source, relationship, target in triples:
        left_var = "n" + secrets.token_hex(4)
        right_var = "n" + secrets.token_hex(4)
        query = (
            f"MATCH ({left_var}:{source})-[:{relationship}]->"
            f"({right_var}:{target}) RETURN {left_var}, {right_var}\n"
        )
        expected = 0 if (source, relationship, target) in ALLOWED_SCHEMA else 1
        cases.append((query, expected))

    # Independently exercise both sides of the maximum-depth boundary.
    depths = list(range(1, MAX_DEPTH + 5))
    random.SystemRandom().shuffle(depths)
    for upper in depths:
        left_var = "c" + secrets.token_hex(4)
        right_var = "c" + secrets.token_hex(4)
        query = (
            f"MATCH ({left_var}:Customer)-[:KNOWS*1..{upper}]->"
            f"({right_var}:Customer) RETURN {right_var}\n"
        )
        expected = 0 if upper <= MAX_DEPTH else 1
        cases.append((query, expected))

    # Unknown relationship names are not members of the allowed schema.
    for _ in range(4):
        relationship = "UNKNOWN_" + secrets.token_hex(5).upper()
        left_var = "c" + secrets.token_hex(3)
        right_var = "p" + secrets.token_hex(3)
        query = (
            f"MATCH ({left_var}:Customer)-[:{relationship}]->"
            f"({right_var}:Product) RETURN {left_var}\n"
        )
        expected = 0 if ("Customer", relationship, "Product") in ALLOWED_SCHEMA else 1
        cases.append((query, expected))

    # Patterns without enough explicit schema information to conflict must pass.
    cases.extend([
        ("MATCH (n) RETURN n\n", 0),
        ("MATCH (a)-[:PURCHASED]->(b) RETURN a, b\n", 0),
        ("MATCH (a:Customer)-[r]->(b:Product) RETURN a, b\n", 0),
    ])

    random.SystemRandom().shuffle(cases)
    hidden_dir = tempfile.mkdtemp(prefix="qf_" + secrets.token_hex(8) + "_")
    failures = []
    try:
        for index, (query, expected) in enumerate(cases):
            filename = f"q_{secrets.token_hex(8)}_{index}.cql"
            filepath = os.path.join(hidden_dir, filename)
            with open(filepath, "w", encoding="utf-8") as handle:
                handle.write(query)
            result = run_filter(filepath)
            if result.returncode != expected:
                failures.append(
                    f"expected exit {expected}, got {result.returncode}: {query.strip()}"
                )
    finally:
        for filename in os.listdir(hidden_dir):
            os.unlink(os.path.join(hidden_dir, filename))
        os.rmdir(hidden_dir)

    assert not failures, "Generated query failures:\n" + "\n".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
