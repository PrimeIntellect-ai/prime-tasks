#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import jsonschema
import pytest

DB_PATH = "/home/user/data/research.db"
METADATA_PATH = "/home/user/data/metadata.jsonl"
SCHEMA_PATH = "/home/user/data/graph_schema.json"
SQL_PATH = "/home/user/scripts/bad_query.sql"
AGGREGATE_PATH = "/home/user/scripts/aggregate.py"
GRAPH_SCRIPT_PATH = "/home/user/scripts/build_graph.py"

EXPECTED_SCHEMA = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "properties": {
        "nodes": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "id": {"type": "string"},
                    "type": {"type": "string", "enum": ["Author", "Paper"]},
                    "label": {"type": "string"},
                },
                "required": ["id", "type", "label"],
            },
        },
        "edges": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "source": {"type": "string"},
                    "target": {"type": "string"},
                    "relation": {"type": "string", "enum": ["AUTHORED"]},
                },
                "required": ["source", "target", "relation"],
            },
        },
    },
    "required": ["nodes", "edges"],
}


def test_pristine_inputs_unchanged():
    assert os.path.isfile(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        tables = {
            row[0] for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )
        }
        assert tables == {"Authors", "Papers", "Author_Paper"}
        assert conn.execute("SELECT author_id, name FROM Authors ORDER BY author_id").fetchall() == [
            (1, "Alice"), (2, "Bob")
        ]
        assert conn.execute("SELECT paper_id, title, year FROM Papers ORDER BY paper_id").fetchall() == [
            (101, "AI Basics", 2020),
            (102, "Advanced ML", 2021),
            (103, "Deep Learning", 2021),
        ]
        assert conn.execute("SELECT author_id, paper_id FROM Author_Paper ORDER BY author_id, paper_id").fetchall() == [
            (1, 101), (1, 102), (2, 102), (2, 103)
        ]
    finally:
        conn.close()

    with open(METADATA_PATH, encoding="utf-8") as f:
        docs = [json.loads(line) for line in f if line.strip()]
    assert docs == [
        {"paper_id": 101, "tags": ["AI", "Intro"]},
        {"paper_id": 102, "tags": ["AI", "ML", "Advanced"]},
        {"paper_id": 103, "tags": ["ML", "Neural Networks"]},
    ]

    with open(SCHEMA_PATH, encoding="utf-8") as f:
        assert json.load(f) == EXPECTED_SCHEMA


def test_fixed_sql_executes_on_independent_database():
    assert os.path.isfile(SQL_PATH), f"File {SQL_PATH} does not exist"
    assert not os.path.islink(SQL_PATH), f"File {SQL_PATH} must not be a symlink"

    token = secrets.token_hex(6)
    ann = "Ann_" + token
    zoe = "Zoe_" + token
    with tempfile.TemporaryDirectory() as td:
        db = os.path.join(td, "fixture.db")
        conn = sqlite3.connect(db)
        conn.executescript("""
            CREATE TABLE Authors (author_id INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE Papers (paper_id INTEGER PRIMARY KEY, title TEXT, year INTEGER);
            CREATE TABLE Author_Paper (author_id INTEGER, paper_id INTEGER);
        """)
        conn.executemany("INSERT INTO Authors VALUES (?, ?)", [(7, zoe), (8, ann)])
        conn.executemany("INSERT INTO Papers VALUES (?, ?, ?)", [
            (201, "One", 2019), (202, "Two", 2021),
            (203, "Three", 2021), (204, "Four", 2020),
        ])
        conn.executemany("INSERT INTO Author_Paper VALUES (?, ?)", [
            (7, 201), (7, 202), (7, 203), (8, 204), (8, 202),
        ])
        conn.commit()
        conn.close()

        result = subprocess.run(
            ["sqlite3", "-header", "-csv", db],
            input=f".read {SQL_PATH}\n",
            text=True,
            capture_output=True,
            timeout=15,
        )
        assert result.returncode == 0, result.stderr
        reader = csv.DictReader(result.stdout.splitlines())
        assert reader.fieldnames == ["name", "year", "yearly_papers", "cumulative_papers"]
        actual = sorted(
            (r["name"], int(r["year"]), int(r["yearly_papers"]), int(r["cumulative_papers"]))
            for r in reader
        )
        assert actual == sorted([
            (zoe, 2019, 1, 1),
            (zoe, 2021, 2, 3),
            (ann, 2020, 1, 1),
            (ann, 2021, 1, 2),
        ])


def test_author_stats_csv():
    csv_path = "/home/user/output/author_stats.csv"
    assert os.path.isfile(csv_path), f"File {csv_path} does not exist"

    with open(csv_path, "r", newline="") as f:
        reader = list(csv.reader(f))
    assert len(reader) > 0, "CSV is empty"
    expected_headers = ["name", "year", "yearly_papers", "cumulative_papers"]
    assert reader[0] == expected_headers

    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute("""
        SELECT a.name, p.year, COUNT(p.paper_id) AS yearly_papers
        FROM Authors a
        JOIN Author_Paper ap ON a.author_id = ap.author_id
        JOIN Papers p ON ap.paper_id = p.paper_id
        GROUP BY a.name, p.year
        ORDER BY a.name, p.year
    """).fetchall()
    conn.close()

    expected_data = []
    cumulative = {}
    for name, year, yearly in rows:
        cumulative[name] = cumulative.get(name, 0) + yearly
        expected_data.append([name, str(year), str(yearly), str(cumulative[name])])
    assert sorted(reader[1:]) == sorted(expected_data)


def test_tag_aggregation_json():
    json_path = "/home/user/output/tag_aggregation.json"
    assert os.path.isfile(json_path), f"File {json_path} does not exist"
    with open(json_path) as f:
        data = json.load(f)
    assert isinstance(data, list)

    tag_counts = {}
    with open(METADATA_PATH) as f:
        for line in f:
            if line.strip():
                for tag in json.loads(line).get("tags", []):
                    tag_counts[tag] = tag_counts.get(tag, 0) + 1
    expected = [{"tag": tag, "count": count} for tag, count in tag_counts.items()]
    expected.sort(key=lambda x: (-x["count"], x["tag"]))
    assert data == expected


def test_graph_json_and_real_schema_validation():
    graph_path = "/home/user/output/graph.json"
    assert os.path.isfile(graph_path), f"File {graph_path} does not exist"
    with open(graph_path) as f:
        data = json.load(f)
    assert "nodes" in data
    assert "edges" in data

    conn = sqlite3.connect(DB_PATH)
    authors = conn.execute("SELECT author_id, name FROM Authors").fetchall()
    papers = conn.execute("SELECT paper_id, title FROM Papers").fetchall()
    author_paper = conn.execute("SELECT author_id, paper_id FROM Author_Paper").fetchall()
    conn.close()

    expected_nodes = [
        {"id": f"A_{aid}", "type": "Author", "label": name} for aid, name in authors
    ] + [
        {"id": f"P_{pid}", "type": "Paper", "label": title} for pid, title in papers
    ]
    expected_edges = [
        {"source": f"A_{aid}", "target": f"P_{pid}", "relation": "AUTHORED"}
        for aid, pid in author_paper
    ]
    assert sorted(data["nodes"], key=lambda n: n["id"]) == sorted(expected_nodes, key=lambda n: n["id"])
    assert sorted(data["edges"], key=lambda e: (e["source"], e["target"], e["relation"])) == sorted(
        expected_edges, key=lambda e: (e["source"], e["target"], e["relation"])
    )

    with open(SCHEMA_PATH) as f:
        schema = json.load(f)
    jsonschema.validate(instance=data, schema=schema)


def test_validation_passed_file():
    passed_path = "/home/user/output/VALIDATION_PASSED"
    assert os.path.isfile(passed_path), f"File {passed_path} does not exist"
    assert os.path.getsize(passed_path) == 0, "VALIDATION_PASSED must be empty"


def test_scripts_execute_on_independent_inputs_and_validate_schema():
    for path in (AGGREGATE_PATH, GRAPH_SCRIPT_PATH):
        assert os.path.isfile(path), f"File {path} does not exist"
        assert not os.path.islink(path), f"File {path} must not be a symlink"
        assert os.path.getsize(path) > 0, f"File {path} is empty"

    output_paths = [
        "/home/user/output/tag_aggregation.json",
        "/home/user/output/graph.json",
        "/home/user/output/VALIDATION_PASSED",
    ]
    with tempfile.TemporaryDirectory() as td:
        input_backups = {}
        output_backups = {}
        for path in (DB_PATH, METADATA_PATH, SCHEMA_PATH):
            backup = os.path.join(td, "input_" + os.path.basename(path))
            shutil.copy2(path, backup)
            input_backups[path] = backup
        for path in output_paths:
            if os.path.exists(path):
                backup = os.path.join(td, "output_" + os.path.basename(path))
                shutil.copy2(path, backup)
                output_backups[path] = backup

        try:
            token = secrets.token_hex(8)
            tags = ["x_" + token, "y_" + token, "z_" + token]
            docs = [
                {"paper_id": 9001, "tags": [tags[0], tags[1]]},
                {"paper_id": 9002, "tags": [tags[0], tags[2]]},
                {"paper_id": 9003, "tags": [tags[0], tags[1]]},
            ]
            with open(METADATA_PATH, "w", encoding="utf-8") as f:
                for doc in docs:
                    f.write(json.dumps(doc) + "\n")
            if os.path.exists(output_paths[0]):
                os.remove(output_paths[0])
            result = subprocess.run(
                ["python3", AGGREGATE_PATH], capture_output=True, text=True, timeout=20
            )
            assert result.returncode == 0, result.stderr
            assert os.path.isfile(output_paths[0])
            with open(output_paths[0]) as f:
                aggregate = json.load(f)
            assert aggregate == [
                {"tag": tags[0], "count": 3},
                {"tag": tags[1], "count": 2},
                {"tag": tags[2], "count": 1},
            ]

            os.remove(DB_PATH)
            conn = sqlite3.connect(DB_PATH)
            conn.executescript("""
                CREATE TABLE Authors (author_id INTEGER PRIMARY KEY, name TEXT);
                CREATE TABLE Papers (paper_id INTEGER PRIMARY KEY, title TEXT, year INTEGER);
                CREATE TABLE Author_Paper (author_id INTEGER, paper_id INTEGER);
            """)
            author_name = "Author_" + token
            paper_title = "Paper_" + token
            conn.execute("INSERT INTO Authors VALUES (?, ?)", (314, author_name))
            conn.execute("INSERT INTO Papers VALUES (?, ?, ?)", (2718, paper_title, 2033))
            conn.execute("INSERT INTO Author_Paper VALUES (?, ?)", (314, 2718))
            conn.commit()
            conn.close()
            with open(SCHEMA_PATH, "w") as f:
                json.dump(EXPECTED_SCHEMA, f)
            for path in output_paths[1:]:
                if os.path.exists(path):
                    os.remove(path)
            result = subprocess.run(
                ["python3", GRAPH_SCRIPT_PATH], capture_output=True, text=True, timeout=20
            )
            assert result.returncode == 0, result.stderr
            with open(output_paths[1]) as f:
                graph = json.load(f)
            assert graph == {
                "nodes": [
                    {"id": "A_314", "type": "Author", "label": author_name},
                    {"id": "P_2718", "type": "Paper", "label": paper_title},
                ],
                "edges": [
                    {"source": "A_314", "target": "P_2718", "relation": "AUTHORED"}
                ],
            }
            jsonschema.validate(graph, EXPECTED_SCHEMA)
            assert os.path.isfile(output_paths[2])
            assert os.path.getsize(output_paths[2]) == 0

            with open(SCHEMA_PATH, "w") as f:
                json.dump({"type": "object", "required": ["missing_required_property"]}, f)
            os.remove(output_paths[2])
            subprocess.run(
                ["python3", GRAPH_SCRIPT_PATH], capture_output=True, text=True, timeout=20
            )
            assert not os.path.exists(output_paths[2]), (
                "build_graph.py created VALIDATION_PASSED even though schema validation must fail"
            )
        finally:
            for path, backup in input_backups.items():
                if os.path.lexists(path):
                    os.remove(path)
                shutil.copy2(backup, path)
            for path in output_paths:
                if os.path.lexists(path):
                    os.remove(path)
                if path in output_backups:
                    shutil.copy2(output_backups[path], path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
