#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import sqlite3
import stat
import subprocess
import time

import pytest

DB_PATH = "/home/user/backups.db"
GO_PATH = "/home/user/analyze_backups.go"
MOD_PATH = "/home/user/go.mod"
JSON_PATH = "/home/user/chain_summary.json"
EXPECTED_KEYS = {"backup_id", "depth", "size_bytes", "running_total_bytes"}


def go_string_literals(source):
    """Extract Go string contents while excluding comments."""
    values = []
    i = 0
    n = len(source)
    while i < n:
        if source.startswith("//", i):
            end = source.find("\n", i + 2)
            i = n if end < 0 else end + 1
        elif source.startswith("/*", i):
            end = source.find("*/", i + 2)
            i = n if end < 0 else end + 2
        elif source[i] == '`':
            end = source.find('`', i + 1)
            assert end >= 0, "Unterminated raw string in Go source."
            values.append(source[i + 1:end])
            i = end + 1
        elif source[i] == '"':
            start = i
            i += 1
            escaped = False
            while i < n:
                ch = source[i]
                if escaped:
                    escaped = False
                elif ch == '\\':
                    escaped = True
                elif ch == '"':
                    i += 1
                    break
                i += 1
            else:
                raise AssertionError("Unterminated quoted string in Go source.")
            token = source[start:i]
            try:
                values.append(json.loads(token))
            except json.JSONDecodeError:
                pass
        elif source[i] == "'":
            # Skip Go rune literals.
            i += 1
            escaped = False
            while i < n:
                ch = source[i]
                i += 1
                if escaped:
                    escaped = False
                elif ch == '\\':
                    escaped = True
                elif ch == "'":
                    break
        else:
            i += 1
    return values


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."
    assert os.path.isfile(GO_PATH), f"Go program {GO_PATH} is missing."
    assert stat.S_ISREG(os.stat(GO_PATH).st_mode), f"{GO_PATH} must be a regular file."
    assert os.path.isfile(MOD_PATH), f"Go module file {MOD_PATH} is missing."

    with open(GO_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    with open(MOD_PATH, "r", encoding="utf-8") as f:
        module_source = f.read()

    assert re.search(r"\bpackage\s+main\b", source), "The submitted file is not a Go main program."
    assert "github.com/mattn/go-sqlite3" in source, "The Go program must import the requested SQLite driver."
    assert "github.com/mattn/go-sqlite3" in module_source, "go.mod must require the requested SQLite driver."

    literals = go_string_literals(source)
    normalized = [re.sub(r"\s+", " ", value).strip() for value in literals]

    index_sql = [
        value for value in normalized
        if re.search(r"(?i)\bCREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?idx_backups_parent\b", value)
    ]
    assert index_sql, "The Go program must contain SQL that creates idx_backups_parent."
    assert any(re.search(r"(?i)\bON\s+(?:\w+\.)?backups\s*\(\s*parent_id\s*\)", value) for value in index_sql), \
        "idx_backups_parent must be created on backups(parent_id)."

    analytical_queries = [value for value in normalized if re.search(r"(?i)\bWITH\s+RECURSIVE\b", value)]
    assert analytical_queries, "The Go program must contain a recursive CTE query."
    assert any(
        re.search(r"(?is)\bSUM\s*\([^)]*size_bytes[^)]*\)\s*OVER\s*\(", value)
        for value in analytical_queries
    ), "The recursive CTE query must use a SUM window function for size_bytes."
    assert re.search(r"\.Query(?:Context)?\s*\(", source), "The Go program must execute its analytical SQL as a query."
    assert re.search(r"\.Exec(?:Context)?\s*\(", source), "The Go program must execute its index-creation SQL."

    # Replace the public fixture with a fresh linear fixture so stale or hardcoded
    # output cannot pass. The required root remains full_alpha.
    token = secrets.token_hex(8)
    tail_id = "inc_alpha_verify_" + token
    sizes = [secrets.randbelow(8000) + 101 for _ in range(6)]

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("DROP INDEX IF EXISTS idx_backups_parent")
        conn.execute("DELETE FROM backups")
        rows = [
            ("full_alpha", None, sizes[0], "2023-11-01 00:00:00"),
            ("inc_alpha_1", "full_alpha", sizes[1], "2023-11-02 00:00:00"),
            ("inc_alpha_2", "inc_alpha_1", sizes[2], "2023-11-03 00:00:00"),
            ("inc_alpha_3", "inc_alpha_2", sizes[3], "2023-11-04 00:00:00"),
            ("inc_alpha_4", "inc_alpha_3", sizes[4], "2023-11-05 00:00:00"),
            (tail_id, "inc_alpha_4", sizes[5], "2023-11-06 00:00:00"),
            ("full_beta", None, 60000, "2023-11-01 00:00:00"),
            ("inc_beta_1", "full_beta", 1000, "2023-11-02 00:00:00"),
        ]
        conn.executemany(
            "INSERT INTO backups(id, parent_id, size_bytes, backup_time) VALUES (?, ?, ?, ?)",
            rows,
        )
        conn.commit()
    finally:
        conn.close()

    if os.path.lexists(JSON_PATH):
        os.remove(JSON_PATH)
    started_ns = time.time_ns()
    result = subprocess.run(
        ["go", "run", GO_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, f"Go program failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(JSON_PATH), f"Go program did not create {JSON_PATH}."
    assert os.stat(JSON_PATH).st_mtime_ns >= started_ns, "JSON output was not generated by this execution."


def test_index_created():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_backups_parent';")
        result = cursor.fetchone()
        assert result is not None, "Index 'idx_backups_parent' was not created in the database."
        assert result[0] == "idx_backups_parent", "Index name does not match expected."
        cursor.execute("PRAGMA index_info('idx_backups_parent')")
        columns = [row[2] for row in cursor.fetchall()]
        assert columns == ["parent_id"], "idx_backups_parent must index exactly parent_id."
    finally:
        conn.close()


def test_json_output():
    assert os.path.exists(JSON_PATH), f"Output JSON file {JSON_PATH} is missing."
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} does not contain valid JSON.")

    assert isinstance(actual_data, list), "JSON output should be a list of objects."

    # Preserve the original independent expected-value computation.
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT id, parent_id, size_bytes FROM backups")
        rows = cursor.fetchall()
    finally:
        conn.close()

    by_id = {row[0]: row for row in rows}
    by_parent = {}
    for row in rows:
        by_parent.setdefault(row[1], []).append(row[0])

    expected_data = []
    current_id = "full_alpha"
    depth = 0
    running_total = 0
    while current_id:
        if current_id not in by_id:
            break
        node = by_id[current_id]
        size_bytes = node[2]
        running_total += size_bytes
        expected_data.append({
            "backup_id": current_id,
            "depth": depth,
            "size_bytes": size_bytes,
            "running_total_bytes": running_total,
        })
        children = by_parent.get(current_id, [])
        if children:
            current_id = children[0]
            depth += 1
        else:
            current_id = None

    assert len(actual_data) == len(expected_data), \
        f"Expected {len(expected_data)} items in JSON, but found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert isinstance(actual, dict), f"Item {i} must be a JSON object."
        assert set(actual.keys()) == EXPECTED_KEYS, \
            f"Item {i} must contain exactly the keys {sorted(EXPECTED_KEYS)}."
        assert isinstance(actual["backup_id"], str), f"backup_id at index {i} must be a string."
        for key in ("depth", "size_bytes", "running_total_bytes"):
            assert isinstance(actual[key], int) and not isinstance(actual[key], bool), \
                f"{key} at index {i} must be an integer."
        assert actual.get("backup_id") == expected["backup_id"], \
            f"Mismatch at index {i}: expected backup_id {expected['backup_id']} but got {actual.get('backup_id')}."
        assert actual.get("depth") == expected["depth"], \
            f"Mismatch at index {i}: expected depth {expected['depth']} but got {actual.get('depth')}."
        assert actual.get("size_bytes") == expected["size_bytes"], \
            f"Mismatch at index {i}: expected size_bytes {expected['size_bytes']} but got {actual.get('size_bytes')}."
        assert actual.get("running_total_bytes") == expected["running_total_bytes"], \
            f"Mismatch at index {i}: expected running_total_bytes {expected['running_total_bytes']} but got {actual.get('running_total_bytes')}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
