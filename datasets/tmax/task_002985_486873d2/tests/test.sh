#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import subprocess
import tempfile

import pytest

BINARY_DIR = "/home/user/cypher_filter"
BINARY_PATH = "/home/user/cypher_filter/target/release/cypher_filter"


@pytest.fixture(scope="module", autouse=True)
def build_rust_project():
    """Ensure the Rust project is built before running tests."""
    if os.path.isdir(BINARY_DIR) and os.path.isfile(os.path.join(BINARY_DIR, "Cargo.toml")):
        subprocess.run(["cargo", "build", "--release"], cwd=BINARY_DIR, capture_output=True)


def test_rust_project_exists():
    assert os.path.isdir(BINARY_DIR), f"Rust project directory {BINARY_DIR} does not exist."
    assert os.path.isfile(os.path.join(BINARY_DIR, "Cargo.toml")), "Cargo.toml not found in the project directory."
    assert os.path.isfile(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}. Ensure it compiles successfully."


def test_clean_corpus_accepted():
    clean_files = glob.glob("/app/corpus/clean/*.cypher")
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_clean = []
    for f in clean_files:
        res = subprocess.run([BINARY_PATH, f], capture_output=True)
        if res.returncode != 0:
            failed_clean.append(os.path.basename(f))

    assert not failed_clean, f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected (expected exit 0): {', '.join(failed_clean)}"


def test_evil_corpus_rejected():
    evil_files = glob.glob("/app/corpus/evil/*.cypher")
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_evil = []
    for f in evil_files:
        res = subprocess.run([BINARY_PATH, f], capture_output=True)
        if res.returncode != 1:
            failed_evil.append(os.path.basename(f))

    assert not failed_evil, f"{len(failed_evil)} of {len(evil_files)} evil bypassed (expected exit 1): {', '.join(failed_evil)}"


def test_generated_novel_queries():
    """Exercise the rule on randomized paths and queries not present in the corpus."""
    rng = random.SystemRandom()
    cases = []

    for _ in range(6):
        a = "n" + secrets.token_hex(5)
        b = "n" + secrets.token_hex(5)
        c = "n" + secrets.token_hex(5)
        label = "L" + secrets.token_hex(3)
        rel = "R" + secrets.token_hex(3)
        number = rng.randrange(10, 100000)
        gap = rng.choice([" ", "  ", "\n", "\t"])
        match_kw = rng.choice(["MATCH", "match", "Match", "mAtCh"])

        # Evil cases are built with two comma-separated, disconnected pattern
        # components in one MATCH clause.
        cases.extend([
            (f"{match_kw}{gap}({a}),{gap}({b}) RETURN {a}, {b}\n", 1),
            (f"{match_kw} ({a}:{label} {{id: {number}}}) ,\n ({b}:{label}) WHERE {a}.id = {b}.id RETURN {a}\n", 1),
            (f"{match_kw} ({a})-[:{rel}]->({b}), ({c}) RETURN {a}, {b}, {c}\n", 1),
        ])

        # Clean cases contain either one pattern component, connected nodes, or
        # commas outside the MATCH pattern (maps, expressions, or RETURN lists).
        cases.extend([
            (f"{match_kw}{gap}({a})-[:{rel}]->({b}) RETURN {a}, {b}\n", 0),
            (f"{match_kw} ({a}:{label} {{x: {number}, y: {number + 1}}}) RETURN {a}\n", 0),
            (f"{match_kw} ({a}) RETURN {a}.x, {a}.y\n", 0),
            (f"{match_kw} ({a}) WHERE coalesce({a}.x, {number}) = {number} RETURN {a}\n", 0),
            (f"RETURN {number}, {number + 1}\n", 0),
        ])

    rng.shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix="cypher_generated_") as case_dir:
        for query, expected in cases:
            path = os.path.join(case_dir, secrets.token_hex(16) + ".cypher")
            with open(path, "w", encoding="utf-8") as query_file:
                query_file.write(query)
            try:
                result = subprocess.run([BINARY_PATH, path], capture_output=True, timeout=5)
                actual = result.returncode
            except subprocess.TimeoutExpired:
                actual = "timeout"
            if actual != expected:
                failures.append((query, expected, actual))

    assert not failures, "Generated query failures:\n" + "\n".join(
        f"expected {expected}, got {actual}: {query!r}"
        for query, expected, actual in failures
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
