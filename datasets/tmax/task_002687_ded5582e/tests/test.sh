#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import sqlite3
import subprocess
import uuid

import pytest

HOME = "/home/user"
DB_PATH = f"{HOME}/system.db"
QUERY_PATH = f"{HOME}/query.sql"
GO_PATH = f"{HOME}/build_graph.go"
SCRIPT_PATH = f"{HOME}/run_etl.sh"
JSON_PATH = f"{HOME}/graph_projection.json"


def run_etl():
    result = subprocess.run(
        ["bash", SCRIPT_PATH],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"run_etl.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} was not generated."


def expected_from_db(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT DISTINCT s1.name as source, s3.name as target
        FROM dependencies d1
        JOIN dependencies d2 ON d1.depends_on_id = d2.service_id
        JOIN services s1 ON d1.service_id = s1.id
        JOIN services s3 ON d2.depends_on_id = s3.id
        WHERE NOT EXISTS (
            SELECT 1 FROM dependencies d3
            WHERE d3.service_id = d1.service_id
              AND d3.depends_on_id = d2.depends_on_id
        )
        ORDER BY source, target;
    """)
    rows = cursor.fetchall()
    conn.close()
    return [{"source": source, "target": target} for source, target in rows]


def load_and_validate_json(expected):
    with open(JSON_PATH, "r") as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} does not contain valid JSON.")

    assert isinstance(actual, list), "JSON output must be a list of objects."
    for item in actual:
        assert isinstance(item, dict), f"Each JSON array item must be an object: {item!r}"
        assert set(item.keys()) == {"source", "target"}, (
            "JSON objects must contain exactly 'source' and 'target' keys. "
            f"Found: {item.keys()}"
        )

    actual_sorted = sorted(actual, key=lambda x: (x.get("source", ""), x.get("target", "")))
    expected_sorted = sorted(expected, key=lambda x: (x["source"], x["target"]))
    assert actual_sorted == expected_sorted, (
        "JSON output does not match expected hidden 2-hop dependencies. "
        f"Expected: {expected_sorted}, Got: {actual_sorted}"
    )
    assert actual == actual_sorted, (
        "The JSON array is not sorted alphabetically by source, then target."
    )


def test_files_exist():
    """Verify that the required script, source, and output files exist."""
    required_files = [QUERY_PATH, GO_PATH, SCRIPT_PATH, JSON_PATH]
    for file_path in required_files:
        assert os.path.isfile(file_path), f"Required file {file_path} is missing."


def test_json_output():
    """Execute the submitted pipeline and verify its output on the provided DB."""
    assert os.path.isfile(DB_PATH), f"{DB_PATH} does not exist."
    run_etl()
    load_and_validate_json(expected_from_db(DB_PATH))


def test_json_structure_and_sorting():
    """Retain the explicit structure and ordering assertions."""
    with open(JSON_PATH, "r") as f:
        actual_json = json.load(f)

    for item in actual_json:
        assert set(item.keys()) == {"source", "target"}, (
            "JSON objects must contain exactly 'source' and 'target' keys. "
            f"Found: {item.keys()}"
        )

    actual_sorted = sorted(actual_json, key=lambda x: (x.get("source", ""), x.get("target", "")))
    assert actual_json == actual_sorted, (
        "The JSON array is not sorted alphabetically by source, then target."
    )


def test_query_go_and_pipeline_on_unseen_data(tmp_path):
    """Exercise the SQL, Go transformer, and shell pipeline on unpredictable data."""
    token = uuid.uuid4().hex
    names = [f"svc_{token}_{i}" for i in range(9)]
    rng = random.SystemRandom()

    # Include duplicate 2-hop paths and a directly connected 2-hop path, then
    # add unpredictable edges so a fixed output cannot pass.
    edges = {
        (1, 2), (2, 3), (1, 4), (4, 3),
        (1, 5), (5, 6), (1, 6),
        (7, 1), (8, 7),
    }
    for source in range(1, 10):
        for target in range(1, 10):
            if source != target and rng.random() < 0.14:
                edges.add((source, target))

    dynamic_db = tmp_path / "dynamic.db"
    conn = sqlite3.connect(dynamic_db)
    conn.executescript("""
        CREATE TABLE services (id INTEGER PRIMARY KEY, name TEXT);
        CREATE TABLE dependencies (service_id INTEGER, depends_on_id INTEGER);
    """)
    conn.executemany(
        "INSERT INTO services(id, name) VALUES (?, ?)",
        [(i + 1, name) for i, name in enumerate(names)],
    )
    conn.executemany(
        "INSERT INTO dependencies(service_id, depends_on_id) VALUES (?, ?)",
        sorted(edges),
    )
    conn.commit()
    conn.close()

    expected = expected_from_db(dynamic_db)
    expected_pairs = {(item["source"], item["target"]) for item in expected}

    # Check that query.sql itself has exactly the required columns and computes
    # the hidden dependencies. Duplicate SQL rows are allowed because the Go
    # stage is also required to deduplicate the final projection.
    query_text = open(QUERY_PATH, "r").read()
    conn = sqlite3.connect(dynamic_db)
    cursor = conn.cursor()
    cursor.execute(query_text)
    assert cursor.description is not None, "query.sql did not return a result set."
    assert [column[0] for column in cursor.description] == ["source", "target"], (
        "query.sql must return exactly two columns named source and target."
    )
    query_rows = cursor.fetchall()
    conn.close()
    assert set(query_rows) == expected_pairs, (
        f"query.sql returned incorrect hidden dependencies. Expected {expected_pairs}, "
        f"got {set(query_rows)}"
    )

    # Check the Go source directly with unordered, duplicated TSV input.
    go_rows = list(expected_pairs)
    if go_rows:
        go_rows.extend([go_rows[0], go_rows[-1]])
    rng.shuffle(go_rows)
    tsv = "".join(f"{source}\t{target}\n" for source, target in go_rows)
    go_result = subprocess.run(
        ["go", "run", GO_PATH],
        input=tsv,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=HOME,
        timeout=60,
    )
    assert go_result.returncode == 0, (
        f"build_graph.go failed.\nstdout:\n{go_result.stdout}\n"
        f"stderr:\n{go_result.stderr}"
    )
    try:
        go_json = json.loads(go_result.stdout)
    except json.JSONDecodeError as exc:
        pytest.fail(f"build_graph.go did not emit valid JSON: {exc}")
    assert go_json == expected, (
        f"build_graph.go must deduplicate and sort TSV edges. Expected {expected}, got {go_json}"
    )
    for item in go_json:
        assert set(item.keys()) == {"source", "target"}

    original_db = tmp_path / "original.db"
    shutil.copy2(DB_PATH, original_db)
    original_query = open(QUERY_PATH, "rb").read()
    original_go = open(GO_PATH, "rb").read()

    try:
        shutil.copy2(dynamic_db, DB_PATH)
        run_etl()
        load_and_validate_json(expected)

        # Verify run_etl.sh actually consumes query.sql and pipes its TSV into
        # the submitted Go source, rather than independently writing JSON.
        sentinel_source = f"source_{uuid.uuid4().hex}"
        sentinel_target = f"target_{uuid.uuid4().hex}"
        marker_source = f"marker_{uuid.uuid4().hex}"
        marker_target = f"marker_{uuid.uuid4().hex}"
        with open(QUERY_PATH, "w") as f:
            f.write(
                "SELECT '" + sentinel_source + "' AS source, '" + sentinel_target + "' AS target;\n"
            )
        replacement_go = f'''package main
import (
    "bufio"
    "encoding/json"
    "os"
    "strings"
)
func main() {{
    scanner := bufio.NewScanner(os.Stdin)
    if !scanner.Scan() || strings.TrimSpace(scanner.Text()) != "{sentinel_source}\\t{sentinel_target}" {{
        os.Exit(41)
    }}
    if scanner.Scan() || scanner.Err() != nil {{
        os.Exit(42)
    }}
    out := []map[string]string{{{{"source": "{marker_source}", "target": "{marker_target}"}}}}
    if json.NewEncoder(os.Stdout).Encode(out) != nil {{
        os.Exit(43)
    }}
}}
'''
        with open(GO_PATH, "w") as f:
            f.write(replacement_go)

        run_etl()
        with open(JSON_PATH, "r") as f:
            controlled = json.load(f)
        assert controlled == [{"source": marker_source, "target": marker_target}], (
            "run_etl.sh must execute query.sql, pipe its tab-separated output into "
            "build_graph.go, and redirect that program's JSON output."
        )
    finally:
        with open(QUERY_PATH, "wb") as f:
            f.write(original_query)
        with open(GO_PATH, "wb") as f:
            f.write(original_go)
        shutil.copy2(original_db, DB_PATH)
        # Leave the required final artifact correct for the restored database.
        run_etl()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
