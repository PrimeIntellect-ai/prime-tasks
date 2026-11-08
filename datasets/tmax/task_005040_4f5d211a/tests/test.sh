#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import sqlite3
import subprocess

import pytest

DB_PATH = "/home/user/backup_mgr.db"
SOURCE_PATH = "/home/user/export_graph.c"
EXEC_PATH = "/home/user/export_graph"
REBUILT_PATH = "/tmp/export_graph_rebuilt"
JSON_PATH = "/home/user/dependency_doc.json"


def sort_deps(d):
    """Recursively sort dependency lists for order-independent comparison."""
    if "dependencies" in d:
        d["dependencies"].sort(key=lambda x: x.get("job", ""))
        for child in d["dependencies"]:
            sort_deps(child)
    return d


def strip_c_comments_and_literals(source):
    pattern = re.compile(
        r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'',
        re.DOTALL,
    )
    return pattern.sub(lambda m: "\n" * m.group(0).count("\n"), source)


def expected_graph(root):
    conn = sqlite3.connect(DB_PATH)
    try:
        def build(alias, ancestors):
            assert alias not in ancestors, "Test database unexpectedly contains a cycle"
            rows = conn.execute(
                """
                SELECT child.bckp_alias
                FROM tbl_bckp_edges AS edge
                JOIN tbl_bckp_manifest AS parent ON parent.idx = edge.src_idx
                JOIN tbl_bckp_manifest AS child ON child.idx = edge.dst_idx
                WHERE parent.bckp_alias = ?
                ORDER BY child.bckp_alias
                """,
                (alias,),
            ).fetchall()
            return {
                "job": alias,
                "dependencies": [build(row[0], ancestors | {alias}) for row in rows],
            }

        exists = conn.execute(
            "SELECT 1 FROM tbl_bckp_manifest WHERE bckp_alias = ?", (root,)
        ).fetchone()
        assert exists is not None
        return build(root, set())
    finally:
        conn.close()


def run_and_read(executable, root):
    try:
        os.remove(JSON_PATH)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        [executable, root],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable} failed for {root!r}: stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert os.path.isfile(JSON_PATH), f"{executable} did not create {JSON_PATH}"
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"{JSON_PATH} is not valid JSON after querying {root!r}: {exc}")
    return sort_deps(data)


def test_c_source_exists_and_uses_prepared_statements():
    assert os.path.exists(SOURCE_PATH), f"C source file missing at {SOURCE_PATH}"
    with open(SOURCE_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "sqlite3_prepare" in content, "C program must use sqlite3_prepare_v2 or similar."
    assert "sqlite3_bind_" in content, "C program must use parameterized queries."

    # Comments and string literals do not count as API use.
    code = strip_c_comments_and_literals(content)
    assert re.search(r"\bsqlite3_prepare(?:_v2|_v3)?\s*\(", code), (
        "C code must actually call a sqlite3_prepare API"
    )
    assert re.search(r"\bsqlite3_bind_(?:int|int64|text|text64)\s*\(", code), (
        "C code must actually call a sqlite3_bind API"
    )


def test_executable_exists():
    assert os.path.exists(EXEC_PATH), f"Compiled executable missing at {EXEC_PATH}"
    assert os.access(EXEC_PATH, os.X_OK), f"File at {EXEC_PATH} is not executable"
    with open(EXEC_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "export_graph must be a compiled executable"


def test_source_compiles():
    result = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", REBUILT_PATH, "-lsqlite3"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"C source does not compile: {result.stderr}"


def test_requires_exactly_one_argument():
    for args in ([], ["app_server_backup", "extra_argument"]):
        result = subprocess.run(
            [EXEC_PATH] + args,
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert result.returncode != 0, f"Program accepted invalid argument list: {args!r}"


def test_executables_traverse_database_for_multiple_and_unseen_jobs():
    token = secrets.token_hex(8)
    probe_root = f"probe_'_root_{token}"
    probe_left = f"probe_left_{token}"
    probe_right = f"probe_right_{token}"
    probe_leaf = f"probe_leaf_{token}"

    conn = sqlite3.connect(DB_PATH)
    try:
        aliases = [probe_root, probe_left, probe_right, probe_leaf]
        ids = {}
        for alias in aliases:
            cur = conn.execute(
                "INSERT INTO tbl_bckp_manifest (bckp_alias) VALUES (?)", (alias,)
            )
            ids[alias] = cur.lastrowid
        conn.executemany(
            "INSERT INTO tbl_bckp_edges (src_idx, dst_idx) VALUES (?, ?)",
            [
                (ids[probe_root], ids[probe_left]),
                (ids[probe_root], ids[probe_right]),
                (ids[probe_left], ids[probe_leaf]),
                (ids[probe_right], ids[probe_leaf]),
            ],
        )
        conn.commit()
    finally:
        conn.close()

    roots = [
        "app_server_backup",
        "user_uploads",
        "network_storage_A",
        probe_root,
        probe_left,
        probe_leaf,
    ]
    for executable in (EXEC_PATH, REBUILT_PATH):
        for root in roots:
            actual = run_and_read(executable, root)
            expected = sort_deps(expected_graph(root))
            assert actual == expected, (
                f"Incorrect dependency graph from {executable} for root {root!r}"
            )


def test_json_output_correctness():
    # Preserve the original final-state assertion and ensure the required final
    # document is generated by actually running the submitted executable.
    data = run_and_read(EXEC_PATH, "app_server_backup")
    expected = {
        "job": "app_server_backup",
        "dependencies": [
            {
                "job": "auth_service",
                "dependencies": [
                    {"job": "network_storage_A", "dependencies": []}
                ],
            },
            {
                "job": "db_cluster_1",
                "dependencies": [
                    {"job": "network_storage_A", "dependencies": []}
                ],
            },
        ],
    }
    assert data == expected, "JSON output does not match the expected dependency graph structure."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
