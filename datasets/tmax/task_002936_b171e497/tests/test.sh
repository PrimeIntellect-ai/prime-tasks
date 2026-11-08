#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import random
import re
import secrets
import sqlite3
import subprocess
import tempfile
import tokenize

SCRIPT_PATH = "/home/user/audit_classifier.py"


def run_classifier(directory, timeout=20):
    return subprocess.run(
        ["python3", SCRIPT_PATH, directory],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def test_audit_classifier_exists():
    """Verify that the agent created the audit_classifier.py script."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}."


def test_uses_required_sql_constructs():
    """The required recursive SQL and index creation must be present."""
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    tokens = []
    for token in tokenize.generate_tokens(io.StringIO(source).readline):
        if token.type != tokenize.COMMENT:
            tokens.append(token)
    uncommented = tokenize.untokenize(tokens)
    assert re.search(r"\bWITH\s+RECURSIVE\b", uncommented, re.IGNORECASE), \
        "Classifier must use a recursive CTE."
    assert re.search(r"\bJOIN\b", uncommented, re.IGNORECASE), \
        "Classifier must use SQL joins."
    assert re.search(r"\bCREATE\s+(?:UNIQUE\s+)?INDEX\b", uncommented, re.IGNORECASE), \
        "Classifier must dynamically create indexes."


def test_audit_classifier_evil_corpus():
    """Verify that the script correctly flags all evil databases as VIOLATION."""
    evil_dir = "/app/corpora/evil/"
    result = run_classifier(evil_dir)
    assert result.returncode == 0, f"Script failed with error:\n{result.stderr}"

    output_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    db_files = [f for f in os.listdir(evil_dir) if f.endswith('.db')]
    failed_files = []
    for db_file in db_files:
        expected_output = f"{db_file}: VIOLATION"
        if expected_output not in output_lines:
            failed_files.append(db_file)
    assert not failed_files, f"{len(failed_files)} of {len(db_files)} evil bypassed. Offending files: {', '.join(failed_files)}"


def test_audit_classifier_clean_corpus():
    """Verify that the script correctly flags all clean databases as CLEAN."""
    clean_dir = "/app/corpora/clean/"
    result = run_classifier(clean_dir)
    assert result.returncode == 0, f"Script failed with error:\n{result.stderr}"

    output_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    db_files = [f for f in os.listdir(clean_dir) if f.endswith('.db')]
    failed_files = []
    for db_file in db_files:
        expected_output = f"{db_file}: CLEAN"
        if expected_output not in output_lines:
            failed_files.append(db_file)
    assert not failed_files, f"{len(failed_files)} of {len(db_files)} clean modified (flagged incorrectly). Offending files: {', '.join(failed_files)}"


def add_path(conn, depth, edge_types=None, destination_jurisdiction="HighRisk", outgoing_type="transfers_to"):
    edge_types = edge_types or ["owns" if i % 2 == 0 else "transfers_to" for i in range(depth)]
    conn.execute("INSERT INTO entities VALUES (1, 'PEP', 'Standard')")
    for step in range(1, depth + 1):
        entity_type = "Shell" if step == depth else "Corp"
        conn.execute("INSERT INTO entities VALUES (?, ?, 'Standard')", (step + 1, entity_type))
        conn.execute(
            "INSERT INTO relations VALUES (?, ?, ?, ?)",
            (step, step + 1, edge_types[step - 1], 100.0 + step),
        )
    conn.execute("INSERT INTO entities VALUES (100, 'Corp', ?)", (destination_jurisdiction,))
    conn.execute(
        "INSERT INTO relations VALUES (?, 100, ?, 250.0)",
        (depth + 1, outgoing_type),
    )


def create_case(path, kind, rng):
    conn = sqlite3.connect(path)
    conn.execute("CREATE TABLE entities (id INTEGER PRIMARY KEY, type TEXT, jurisdiction TEXT)")
    conn.execute("CREATE TABLE relations (source INTEGER, target INTEGER, rel_type TEXT, amount REAL)")

    noise_count = rng.randint(18, 38)
    for i in range(1000, 1000 + noise_count):
        conn.execute("INSERT INTO entities VALUES (?, 'Corp', 'Standard')", (i,))
    for i in range(1000, 999 + noise_count):
        conn.execute("INSERT INTO relations VALUES (?, ?, 'owns', 1.0)", (i, i + 1))

    if kind.startswith("violation"):
        add_path(conn, int(kind[-1]))
    elif kind == "depth4":
        add_path(conn, 4)
    elif kind == "bad_edge":
        add_path(conn, 2, edge_types=["owns", "advises"])
    elif kind == "standard_destination":
        add_path(conn, 2, destination_jurisdiction="Standard")
    elif kind == "wrong_outgoing":
        add_path(conn, 3, outgoing_type="owns")
    elif kind == "reverse_chain":
        conn.execute("INSERT INTO entities VALUES (1, 'PEP', 'Standard')")
        conn.execute("INSERT INTO entities VALUES (2, 'Corp', 'Standard')")
        conn.execute("INSERT INTO entities VALUES (3, 'Shell', 'Standard')")
        conn.execute("INSERT INTO entities VALUES (100, 'Corp', 'HighRisk')")
        conn.execute("INSERT INTO relations VALUES (3, 2, 'owns', 10.0)")
        conn.execute("INSERT INTO relations VALUES (2, 1, 'transfers_to', 10.0)")
        conn.execute("INSERT INTO relations VALUES (3, 100, 'transfers_to', 10.0)")
    else:
        raise AssertionError(f"Unknown generated case: {kind}")
    conn.commit()
    conn.close()


def oracle_violation(path):
    conn = sqlite3.connect(path)
    row = conn.execute("""
        WITH RECURSIVE reachable(node, depth) AS (
            SELECT r.target, 1
            FROM entities AS p
            JOIN relations AS r ON r.source = p.id
            WHERE p.type = 'PEP'
              AND r.rel_type IN ('owns', 'transfers_to')
            UNION ALL
            SELECT r.target, reachable.depth + 1
            FROM reachable
            JOIN relations AS r ON r.source = reachable.node
            WHERE reachable.depth < 3
              AND r.rel_type IN ('owns', 'transfers_to')
        )
        SELECT 1
        FROM reachable
        JOIN entities AS shell ON shell.id = reachable.node AND shell.type = 'Shell'
        JOIN relations AS payout
          ON payout.source = shell.id AND payout.rel_type = 'transfers_to'
        JOIN entities AS destination
          ON destination.id = payout.target AND destination.jurisdiction = 'HighRisk'
        WHERE reachable.depth BETWEEN 1 AND 3
        LIMIT 1
    """).fetchone()
    conn.close()
    return row is not None


def assert_relation_indexes(path):
    conn = sqlite3.connect(path)
    indexed_columns = set()
    for row in conn.execute("PRAGMA index_list('relations')"):
        index_name = row[1].replace('"', '""')
        for info in conn.execute(f'PRAGMA index_info("{index_name}")'):
            indexed_columns.add(info[2])
    conn.close()
    assert "source" in indexed_columns and "target" in indexed_columns, \
        f"Classifier did not create indexes covering relations.source and relations.target in {path}"


def test_randomized_mixed_corpus_exact_output_and_indexes():
    """Exercise unpredictable names and independently derive every expected answer."""
    rng = random.SystemRandom()
    kinds = [
        "violation1", "violation2", "violation3", "depth4",
        "bad_edge", "standard_destination", "wrong_outgoing", "reverse_chain",
    ]
    rng.shuffle(kinds)

    with tempfile.TemporaryDirectory(prefix="audit_case_") as directory:
        paths = []
        for kind in kinds:
            filename = f"region_{secrets.token_hex(10)}.db"
            path = os.path.join(directory, filename)
            create_case(path, kind, rng)
            paths.append(path)

        expected = []
        for path in paths:
            label = "VIOLATION" if oracle_violation(path) else "CLEAN"
            expected.append(f"{os.path.basename(path)}: {label}")
        assert any(line.endswith(": VIOLATION") for line in expected)
        assert any(line.endswith(": CLEAN") for line in expected)

        result = run_classifier(directory)
        assert result.returncode == 0, f"Script failed with error:\n{result.stderr}"
        actual = result.stdout.splitlines()
        assert len(actual) == len(expected), \
            f"Expected exactly one output line per database; got {actual!r}"
        assert sorted(actual) == sorted(expected), \
            f"Incorrect classifier output. Expected {sorted(expected)!r}, got {sorted(actual)!r}"

        for path in paths:
            assert_relation_indexes(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
