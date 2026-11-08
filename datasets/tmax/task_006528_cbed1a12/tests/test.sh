#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import sqlite3
import subprocess
from pathlib import Path

import jsonschema
import pytest

DB_PATH = "/home/user/citations.db"
JSON_PATH = Path("/home/user/shortest_path.json")
SCHEMA_PATH = "/home/user/schema.json"


def load_and_validate_json():
    assert JSON_PATH.exists(), f"JSON file missing: {JSON_PATH}"
    try:
        with JSON_PATH.open("r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {JSON_PATH} is not valid JSON.")

    with open(SCHEMA_PATH, "r") as f:
        schema = json.load(f)
    jsonschema.validate(data, schema)
    return data


def test_indexes_created():
    assert os.path.exists(DB_PATH), f"Database file missing: {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='citations';")
    indexes = cursor.fetchall()
    assert len(indexes) > 0, "No indexes found on 'citations' table. You need to create optimal indexes for graph traversal."

    cursor.execute("PRAGMA index_list('citations')")
    index_rows = cursor.fetchall()
    leading_columns = set()
    for row in index_rows:
        name = row[1]
        partial = bool(row[4]) if len(row) > 4 else False
        if partial:
            continue
        cursor.execute("SELECT name FROM pragma_index_info(?) ORDER BY seqno", (name,))
        columns = [r[0] for r in cursor.fetchall()]
        if columns:
            leading_columns.add(columns[0])

    assert "source_id" in leading_columns, "Missing an index led by source_id for outgoing citation traversal."
    assert "target_id" in leading_columns, "Missing an index led by target_id for incoming citation traversal."
    conn.close()


def test_shortest_path_json():
    data = load_and_validate_json()

    assert "path_length" in data, "Missing 'path_length' key in JSON."
    assert "path" in data, "Missing 'path' key in JSON."
    assert data["path_length"] == 2, f"Expected path_length to be 2, got {data['path_length']}."

    expected_path = [
        {"id": "P1", "title": "Deep Learning"},
        {"id": "P4", "title": "Optimization Methods"},
        {"id": "P5", "title": "Adam Optimizer"}
    ]
    assert data["path"] == expected_path, f"Expected path {expected_path}, got {data['path']}."


def test_python_script_computes_result_from_database():
    scripts = []
    excluded_dirs = {".git", ".venv", "venv", "__pycache__", "site-packages"}
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in excluded_dirs and not d.startswith(".")]
        for filename in files:
            path = Path(root) / filename
            if path.suffix == ".py" and path.is_file() and not path.is_symlink():
                scripts.append(path)

    assert scripts, "No Python script was created under /home/user."

    original_json = JSON_PATH.read_bytes() if JSON_PATH.exists() else None
    conn = sqlite3.connect(DB_PATH)
    original_papers = conn.execute("SELECT id, title FROM papers").fetchall()
    original_citations = conn.execute("SELECT source_id, target_id FROM citations").fetchall()
    conn.close()

    rng = secrets.SystemRandom()
    middle = ["P2", "P3", "P4"]
    rng.shuffle(middle)
    route = ["P1"] + middle[:rng.randrange(4)] + ["P5"]
    titles = {pid: f"Title-{pid}-{secrets.token_hex(8)}" for pid in ["P1", "P2", "P3", "P4", "P5"]}
    expected = {
        "path_length": len(route) - 1,
        "path": [{"id": pid, "title": titles[pid]} for pid in route],
    }

    def install_test_graph():
        db = sqlite3.connect(DB_PATH)
        db.execute("DELETE FROM citations")
        db.execute("DELETE FROM papers")
        db.executemany("INSERT INTO papers(id, title) VALUES (?, ?)", list(titles.items()))
        db.executemany(
            "INSERT INTO citations(source_id, target_id) VALUES (?, ?)",
            list(zip(route, route[1:])),
        )
        db.commit()
        db.close()

    errors = []
    matched_script = None
    try:
        for script in sorted(scripts):
            install_test_graph()
            if JSON_PATH.exists():
                JSON_PATH.unlink()
            try:
                result = subprocess.run(
                    ["python3", str(script)],
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=15,
                )
            except (OSError, subprocess.TimeoutExpired) as exc:
                errors.append(f"{script}: {exc}")
                continue

            if result.returncode != 0:
                errors.append(f"{script}: exited {result.returncode}: {result.stderr[-300:]}")
                continue
            if not JSON_PATH.exists():
                errors.append(f"{script}: did not create {JSON_PATH}")
                continue

            try:
                data = load_and_validate_json()
            except Exception as exc:
                errors.append(f"{script}: invalid output: {exc}")
                continue

            if data == expected:
                matched_script = script
                break
            errors.append(f"{script}: output did not match the shortest path derived from the database")

        assert matched_script is not None, "No created Python script computed the requested result from the database. " + " | ".join(errors)
    finally:
        db = sqlite3.connect(DB_PATH)
        db.execute("DELETE FROM citations")
        db.execute("DELETE FROM papers")
        db.executemany("INSERT INTO papers(id, title) VALUES (?, ?)", original_papers)
        db.executemany("INSERT INTO citations(source_id, target_id) VALUES (?, ?)", original_citations)
        db.commit()
        db.close()

        if original_json is None:
            if JSON_PATH.exists():
                JSON_PATH.unlink()
        else:
            JSON_PATH.write_bytes(original_json)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
