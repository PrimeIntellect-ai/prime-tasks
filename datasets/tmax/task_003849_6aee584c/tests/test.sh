#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import subprocess
import uuid

DB_PATH = "/home/user/datasets.db"
GO_SCRIPT_PATH = "/home/user/graph_query.go"
OUTPUT_PATH = "/home/user/top_consumers.txt"
BINARY_PATH = "/tmp/graph_query_verifier"


def read_names(text):
    return [line.strip() for line in text.splitlines() if line.strip()]


def expected_consumers(conn, target_name):
    rows = conn.execute(
        "SELECT id, name, size_mb, domain FROM datasets"
    ).fetchall()
    by_id = {row[0]: row for row in rows}
    target_ids = [row[0] for row in rows if row[1] == target_name]
    assert len(target_ids) == 1, f"Expected one target named {target_name!r}"

    dependents = {}
    for source_id, target_id in conn.execute(
        "SELECT source_id, target_id FROM dependencies"
    ):
        dependents.setdefault(target_id, []).append(source_id)

    reachable = set()
    pending = list(dependents.get(target_ids[0], []))
    while pending:
        dataset_id = pending.pop()
        if dataset_id in reachable:
            continue
        reachable.add(dataset_id)
        pending.extend(dependents.get(dataset_id, []))

    matches = [by_id[i] for i in reachable if i in by_id and by_id[i][3] == "Genomics"]
    matches.sort(key=lambda row: (-row[2], row[1]))
    return [row[1] for row in matches[:3]]


def run_program(target_name):
    proc = subprocess.run(
        [BINARY_PATH, target_name],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert proc.returncode == 0, (
        f"graph_query.go failed for {target_name!r} with exit code "
        f"{proc.returncode}: {proc.stderr}"
    )
    return read_names(proc.stdout)


def test_output_file_contents():
    """Verify that the output file contains the exactly correct top 3 consumers."""
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."

    with open(OUTPUT_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "Clinical_Correlations",
        "GWAS_Summary",
        "Population_Frequencies",
    ]

    assert lines == expected_lines, f"Expected {expected_lines}, but got {lines}. The Go script did not produce the correct output."


def test_database_indexes():
    """Verify that appropriate indexes were created to optimize the queries."""
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index';")
    indexes = cursor.fetchall()

    indexed_tables = [idx[1] for idx in indexes]
    assert "dependencies" in indexed_tables, "No index was created on the 'dependencies' table to optimize graph traversal."
    assert "datasets" in indexed_tables, "No index was created on the 'datasets' table to optimize filtering/sorting."

    index_columns = {}
    for index_name, table_name in indexes:
        escaped = index_name.replace('"', '""')
        columns = [
            row[2]
            for row in cursor.execute(f'PRAGMA index_info("{escaped}")').fetchall()
        ]
        index_columns.setdefault(table_name, []).append(columns)

    assert any(cols and cols[0] == "target_id" for cols in index_columns.get("dependencies", [])), (
        "The dependencies table needs an index whose leading column is target_id."
    )
    assert any(
        len(cols) >= 2 and cols[0] == "domain" and "size_mb" in cols[1:]
        for cols in index_columns.get("datasets", [])
    ), "The datasets table needs a composite index beginning with domain and including size_mb."
    conn.close()


def test_go_script_exists_and_content():
    """Verify that the Go script exists and contains expected SQL and imports."""
    assert os.path.exists(GO_SCRIPT_PATH), f"Go script {GO_SCRIPT_PATH} does not exist."

    with open(GO_SCRIPT_PATH, "r") as f:
        content = f.read()

    assert "database/sql" in content, "Go script does not import 'database/sql'."
    assert "github.com/mattn/go-sqlite3" in content, "Go script does not import the sqlite3 driver."
    assert "WITH RECURSIVE" in content.upper(), "Go script does not appear to use a Recursive CTE."
    assert "os.Args" in content or "flag." in content, "Go script does not appear to read command-line arguments."


def test_go_script_compiles_and_executes_real_queries():
    env = os.environ.copy()
    env["HOME"] = "/home/user"
    env["GOCACHE"] = "/tmp/verifier-go-cache"
    build = subprocess.run(
        ["go", "build", "-o", BINARY_PATH, GO_SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert build.returncode == 0, f"graph_query.go does not compile: {build.stderr}"

    conn = sqlite3.connect(DB_PATH)
    try:
        expected_base = expected_consumers(conn, "Base_Sequences")
        assert run_program("Base_Sequences") == expected_base

        token = uuid.uuid4().hex
        target_name = f"Verifier_Target_'_{token}"
        names = [f"Verifier_Consumer_{i}_{token}" for i in range(6)]
        base_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 100 FROM datasets").fetchone()[0]

        inserted_ids = [base_id + i for i in range(7)]
        conn.execute(
            "INSERT INTO datasets(id, name, size_mb, domain) VALUES (?, ?, ?, ?)",
            (inserted_ids[0], target_name, 999999, "Genomics"),
        )
        consumer_rows = [
            (inserted_ids[1], names[0], 1100, "Genomics"),
            (inserted_ids[2], names[1], 5300, "Genomics"),
            (inserted_ids[3], names[2], 3200, "Genomics"),
            (inserted_ids[4], names[3], 7400, "Genomics"),
            (inserted_ids[5], names[4], 4600, "Genomics"),
            (inserted_ids[6], names[5], 900000, "Proteomics"),
        ]
        conn.executemany(
            "INSERT INTO datasets(id, name, size_mb, domain) VALUES (?, ?, ?, ?)",
            consumer_rows,
        )
        edges = [
            (inserted_ids[1], inserted_ids[0]),
            (inserted_ids[2], inserted_ids[1]),
            (inserted_ids[3], inserted_ids[2]),
            (inserted_ids[4], inserted_ids[0]),
            (inserted_ids[5], inserted_ids[4]),
            (inserted_ids[6], inserted_ids[3]),
        ]
        conn.executemany(
            "INSERT INTO dependencies(source_id, target_id) VALUES (?, ?)", edges
        )
        conn.commit()

        expected = expected_consumers(conn, target_name)
        actual = run_program(target_name)
        assert actual == expected, f"Expected dynamic query result {expected}, got {actual}"
    finally:
        try:
            conn.execute(
                "DELETE FROM dependencies WHERE source_id BETWEEN ? AND ? OR target_id BETWEEN ? AND ?",
                (base_id, base_id + 6, base_id, base_id + 6),
            )
            conn.execute("DELETE FROM datasets WHERE id BETWEEN ? AND ?", (base_id, base_id + 6))
            conn.commit()
        except Exception:
            conn.rollback()
        conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
