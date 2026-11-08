#!/bin/bash
set -e
mkdir -p /logs/verifier

DB_PATH=/home/user/citation_graph.db
DB_BACKUP=$(mktemp)
cp "$DB_PATH" "$DB_BACKUP"
cleanup() {
    rm -f "${DB_PATH}-wal" "${DB_PATH}-shm"
    cp "$DB_BACKUP" "$DB_PATH"
    rm -f "$DB_BACKUP"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import sqlite3
import subprocess

import pytest

C_SOURCE_PATH = "/home/user/process_graph.c"
EXEC_PATH = "/home/user/process_graph"
JSON_OUTPUT_PATH = "/home/user/valid_nodes.json"
REBUILT_EXEC_PATH = "/tmp/process_graph_rebuilt"


def load_output():
    assert os.path.isfile(JSON_OUTPUT_PATH), f"JSON output file missing at {JSON_OUTPUT_PATH}"
    with open(JSON_OUTPUT_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {JSON_OUTPUT_PATH} as JSON: {e}")
    assert isinstance(data, list), "JSON output must be a list (array) of objects."
    for item in data:
        assert isinstance(item, dict), "Every JSON array element must be an object."
        assert set(item) == {"id", "title"}, f"Unexpected object schema: {item}"
        assert isinstance(item["id"], int) and not isinstance(item["id"], bool), f"Invalid id: {item}"
        assert isinstance(item["title"], str) and item["title"] != "", f"Invalid title: {item}"
    return sorted(data, key=lambda x: x["id"])


def run_and_load(executable, source_id, target_id):
    try:
        result = subprocess.run(
            [executable, str(source_id), str(target_id)],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Executable timed out for IDs {source_id}, {target_id}")
    assert result.returncode == 0, (
        f"Executable failed for IDs {source_id}, {target_id} with return code "
        f"{result.returncode}. Stderr: {result.stderr}"
    )
    return load_output()


def expected_from_database(source_id, target_id):
    with sqlite3.connect("/home/user/citation_graph.db") as con:
        rows = con.execute(
            """
            SELECT DISTINCT p.id, p.title
            FROM citations AS incoming
            JOIN citations AS outgoing ON outgoing.from_id = incoming.to_id
            JOIN papers AS p ON p.id = incoming.to_id
            WHERE incoming.from_id = ? AND outgoing.to_id = ?
              AND p.title IS NOT NULL AND p.title <> ''
            """,
            (source_id, target_id),
        ).fetchall()
    return sorted(({"id": row[0], "title": row[1]} for row in rows), key=lambda x: x["id"])


def test_c_source_exists():
    """Test that the C source code file exists."""
    assert os.path.isfile(C_SOURCE_PATH), f"C source file missing at {C_SOURCE_PATH}"


def test_executable_exists_and_runnable():
    """Test that the compiled executable exists and is executable."""
    assert os.path.isfile(EXEC_PATH), f"Compiled executable missing at {EXEC_PATH}"
    assert os.access(EXEC_PATH, os.X_OK), f"File at {EXEC_PATH} is not executable"
    with open(EXEC_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "process_graph must be a compiled executable"


def test_json_output_contents():
    """Test that the valid_nodes.json file contains the correct JSON array."""
    data = load_output()
    expected_data = [
        {"id": 20, "title": "Valid Bridge 1"},
        {"id": 21, "title": "Valid Bridge 2"},
    ]
    assert data == expected_data, f"JSON contents do not match expected output. Got: {data}"


def test_executable_behavior():
    """Test that running the executable produces the correct output file."""
    data = run_and_load(EXEC_PATH, 10, 50)
    expected_data = [
        {"id": 20, "title": "Valid Bridge 1"},
        {"id": 21, "title": "Valid Bridge 2"},
    ]
    assert data == expected_data, f"Executable did not produce the correct JSON output. Got: {data}"


def test_source_uses_sqlite_parameter_binding():
    with open(C_SOURCE_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    source_without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    assert re.search(r"\bsqlite3_open(?:_v2)?\s*\(", source_without_comments), "C source must open SQLite"
    assert re.search(r"\bsqlite3_prepare(?:_v2|_v3)?\s*\(", source_without_comments), "C source must prepare a query"
    assert re.search(r"\bsqlite3_bind_[A-Za-z0-9_]+\s*\(", source_without_comments), "C source must bind query parameters"
    assert re.search(r"\bsqlite3_column_text\s*\(", source_without_comments), "C source must read titles in C"


@pytest.fixture(scope="session")
def rebuilt_exec():
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", C_SOURCE_PATH, "-lsqlite3", "-o", REBUILT_EXEC_PATH],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"C source failed to compile. Stderr: {result.stderr}"
    assert os.access(REBUILT_EXEC_PATH, os.X_OK)
    return REBUILT_EXEC_PATH


def allocate_ids(con, count):
    used = {row[0] for row in con.execute("SELECT id FROM papers")}
    result = []
    while len(result) < count:
        candidate = secrets.randbelow(1_500_000_000) + 100_000
        if candidate not in used:
            used.add(candidate)
            result.append(candidate)
    return result


def test_randomized_database_behavior_and_validation(rebuilt_exec):
    with sqlite3.connect("/home/user/citation_graph.db") as con:
        (source, target, good1, good2, null_node, empty_node,
         wrong_target_node, uncited_node, source2, target2, good3) = allocate_ids(con, 11)

        title1 = 'Dynamic "Bridge" \\ line\nsecond Ω ' + secrets.token_hex(8)
        title2 = "Another dynamic bridge " + secrets.token_hex(8)
        title3 = "Independent bridge " + secrets.token_hex(8)

        con.executemany(
            "INSERT INTO papers(id, title) VALUES (?, ?)",
            [
                (source, "dynamic source"), (target, "dynamic target"),
                (good1, title1), (good2, title2), (null_node, None),
                (empty_node, ""), (wrong_target_node, "wrong target"),
                (uncited_node, "not cited by source"),
                (source2, "second source"), (target2, "second target"),
                (good3, title3),
            ],
        )
        con.executemany(
            "INSERT INTO citations(from_id, to_id) VALUES (?, ?)",
            [
                (source, good1), (source, good2), (source, null_node),
                (source, empty_node), (source, wrong_target_node),
                (good1, target), (good2, target), (null_node, target),
                (empty_node, target), (uncited_node, target),
                (wrong_target_node, target2),
                (source2, good3), (good3, target2),
            ],
        )
        con.commit()

    for executable in (EXEC_PATH, rebuilt_exec):
        expected = expected_from_database(source, target)
        assert run_and_load(executable, source, target) == expected
        assert run_and_load(executable, source2, target2) == expected_from_database(source2, target2)
        assert run_and_load(executable, target, source) == expected_from_database(target, source)

        changed_title = "Changed at verification time " + secrets.token_hex(12)
        with sqlite3.connect("/home/user/citation_graph.db") as con:
            con.execute("UPDATE papers SET title = ? WHERE id = ?", (changed_title, good1))
            con.commit()
        assert run_and_load(executable, source, target) == expected_from_database(source, target)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
