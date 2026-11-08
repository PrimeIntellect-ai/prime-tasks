#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import sqlite3
import subprocess

BASE = "/home/user/analytics"
GO_FILE = os.path.join(BASE, "build_graph.go")
CSV_FILE = os.path.join(BASE, "network.csv")
DB_FILE = os.path.join(BASE, "graph.db")
OUTPUT_FILE = os.path.join(BASE, "output.json")

ORIGINAL_EXPECTED = [
    {
        "source_node": "A",
        "total_interactions": 11,
        "connections": [
            {"target_node": "B", "weight": 5},
            {"target_node": "C", "weight": 6},
        ],
    },
    {
        "source_node": "D",
        "total_interactions": 16,
        "connections": [
            {"target_node": "A", "weight": 15},
            {"target_node": "B", "weight": 1},
        ],
    },
    {
        "source_node": "G",
        "total_interactions": 12,
        "connections": [{"target_node": "H", "weight": 12}],
    },
    {
        "source_node": "H",
        "total_interactions": 20,
        "connections": [
            {"target_node": "A", "weight": 10},
            {"target_node": "B", "weight": 10},
        ],
    },
]


def read_output():
    assert os.path.isfile(OUTPUT_FILE), f"File {OUTPUT_FILE} does not exist."
    with open(OUTPUT_FILE, encoding="utf-8") as f:
        return json.load(f)


def expected_projection(rows, threshold):
    grouped = {}
    for source, target, weight in rows:
        entry = grouped.setdefault(source, {"total": 0, "connections": []})
        entry["total"] += weight
        entry["connections"].append(
            {"target_node": target, "weight": weight}
        )

    result = []
    for source in sorted(grouped):
        entry = grouped[source]
        if entry["total"] > threshold:
            result.append({
                "source_node": source,
                "total_interactions": entry["total"],
                "connections": sorted(
                    entry["connections"], key=lambda item: item["target_node"]
                ),
            })
    return result


def write_csv(rows):
    with open(CSV_FILE, "w", newline="", encoding="utf-8") as f:
        csv.writer(f).writerows(rows)


def run_program(threshold):
    completed = subprocess.run(
        ["go", "run", "build_graph.go", str(threshold)],
        cwd=BASE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert completed.returncode == 0, (
        f"go run failed for threshold {threshold}\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def assert_database(rows):
    assert os.path.isfile(DB_FILE), f"File {DB_FILE} does not exist."
    with sqlite3.connect(DB_FILE) as db:
        table = db.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='edges'"
        ).fetchone()
        assert table is not None, "SQLite database does not contain an edges table."

        columns = [row[1] for row in db.execute("PRAGMA table_info(edges)")]
        assert all(name in columns for name in ("source", "target", "interaction_count")), (
            f"edges table has incorrect columns: {columns}"
        )
        actual = db.execute(
            "SELECT source, target, interaction_count FROM edges"
        ).fetchall()

    normalized_actual = sorted((str(s), str(t), int(w)) for s, t, w in actual)
    normalized_expected = sorted(rows)
    assert normalized_actual == normalized_expected, (
        "The edges table does not contain exactly the current CSV data."
    )


def test_go_file_exists():
    assert os.path.isfile(GO_FILE), f"File {GO_FILE} does not exist."


def test_database_exists():
    assert os.path.isfile(DB_FILE), f"File {DB_FILE} does not exist."


def test_output_json_exists_and_content():
    assert read_output() == ORIGINAL_EXPECTED, (
        "The contents of output.json do not match the expected graph projection."
    )


def test_source_contains_parameterized_aggregate_sql():
    with open(GO_FILE, encoding="utf-8") as f:
        source = f.read()

    assert '"database/sql"' in source, "Program must use Go's database/sql package."
    sql_literals = re.findall(r'`[^`]*`|"(?:\\.|[^"\\])*"', source, flags=re.S)
    aggregate_literals = [literal for literal in sql_literals if re.search(r'(?i)\bSUM\s*\(', literal)]
    assert aggregate_literals, "No SQL aggregate query using SUM was found."
    assert any("?" in literal for literal in aggregate_literals), (
        "The aggregate SQL query must contain a parameter placeholder."
    )
    assert re.search(r'\.(?:Query|QueryRow|Exec|Prepare)(?:Context)?\s*\(', source), (
        "No database query or prepared-statement execution was found."
    )


def test_program_executes_and_handles_unseen_inputs():
    with open(CSV_FILE, "rb") as f:
        original_csv = f.read()

    try:
        original_rows = [
            ("A", "B", 5), ("A", "C", 6), ("B", "C", 2),
            ("D", "A", 15), ("D", "B", 1), ("E", "F", 5),
            ("G", "H", 12), ("H", "A", 10), ("H", "B", 10),
        ]
        run_program(10)
        assert read_output() == ORIGINAL_EXPECTED
        assert_database(original_rows)

        token = secrets.token_hex(5)
        threshold = 7 + secrets.randbelow(17)
        rows = [
            (f"Alpha_{token}", "z_target", threshold),
            (f"Alpha_{token}", "a_target", 1),
            (f"Exact_{token}", "only", threshold),
            (f"O'Brien_{token}", "left", threshold + 2),
            (f"O'Brien_{token}", "right", threshold + 3),
            (f"Small_{token}", "tail", 1),
        ]
        write_csv(rows)

        run_program(threshold)
        assert read_output() == expected_projection(rows, threshold)
        assert_database(rows)

        second_threshold = 2 * threshold + 5
        run_program(second_threshold)
        assert read_output() == expected_projection(rows, second_threshold)
        assert_database(rows)
    finally:
        with open(CSV_FILE, "wb") as f:
            f.write(original_csv)
        subprocess.run(
            ["go", "run", "build_graph.go", "10"],
            cwd=BASE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
