#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile
from pathlib import Path

import pytest


def test_stale_edges_file():
    txt_path = "/home/user/stale_edges.txt"
    assert os.path.isfile(txt_path), f"File {txt_path} does not exist."

    with open(txt_path, "r") as f:
        lines = [line.strip() for line in f.read().splitlines() if line.strip()]

    # The initial DB has ids 1,2,3,4,5 and truth has 1,2,4. Stale are 3, 5.
    expected_stale = ["3", "5"]
    assert lines == expected_stale, f"Expected stale_edges.txt to contain exactly {expected_stale}, but got {lines}."


def test_rust_program_on_derived_fixture():
    project = Path("/home/user/graph_project")
    main_rs = project / "src/main.rs"
    manifest = project / "Cargo.toml"
    assert main_rs.is_file(), f"Rust source {main_rs} does not exist."
    assert manifest.is_file(), f"Cargo manifest {manifest} does not exist."

    metadata_run = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps", "--manifest-path", str(manifest)],
        cwd=project,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert metadata_run.returncode == 0, f"cargo metadata failed:\n{metadata_run.stderr}"
    metadata = json.loads(metadata_run.stdout)
    expected_source = main_rs.resolve()
    matching_targets = [
        target
        for package in metadata["packages"]
        for target in package.get("targets", [])
        if target.get("name") == "graph_project"
        and "bin" in target.get("kind", [])
        and Path(target["src_path"]).resolve() == expected_source
    ]
    assert matching_targets, "Cargo's graph_project binary target must be built from src/main.rs."

    build = subprocess.run(
        ["cargo", "build", "--manifest-path", str(manifest), "--message-format=json"],
        cwd=project,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=300,
    )
    assert build.returncode == 0, f"Rust project failed to compile:\n{build.stderr}"

    executable = None
    for line in build.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        target = message.get("target", {})
        if (
            message.get("reason") == "compiler-artifact"
            and target.get("name") == "graph_project"
            and "bin" in target.get("kind", [])
            and message.get("executable")
            and Path(target.get("src_path", "")).resolve() == expected_source
        ):
            executable = Path(message["executable"])
    assert executable is not None and executable.is_file(), "Cargo did not produce the required graph_project executable."

    db_path = Path("/home/user/data/graph.db")
    json_path = Path("/home/user/data/truth_edges.json")
    output_path = Path("/home/user/stale_edges.txt")

    rng = random.SystemRandom()
    ids = rng.sample(range(10000, 900000), 8)
    truth_ids = set(rng.sample(ids, 5))
    db_rows = [(edge_id, rng.randrange(1, 1000000), rng.randrange(1, 1000000)) for edge_id in ids]
    truth_rows = [
        {"id": edge_id, "source": source, "target": target}
        for edge_id, source, target in db_rows
        if edge_id in truth_ids
    ]
    rng.shuffle(truth_rows)
    expected = [str(edge_id) for edge_id in sorted(set(ids) - truth_ids)]

    with tempfile.TemporaryDirectory() as temp_dir:
        temp = Path(temp_dir)
        saved = {}
        paths_to_preserve = [db_path, Path(str(db_path) + "-wal"), Path(str(db_path) + "-shm"), json_path, output_path]
        for path in paths_to_preserve:
            if path.exists() or path.is_symlink():
                backup = temp / (path.name + ".saved")
                os.replace(path, backup)
                saved[path] = backup

        try:
            conn = sqlite3.connect(db_path)
            conn.execute("CREATE TABLE edges (id INTEGER PRIMARY KEY, source INTEGER, target INTEGER)")
            conn.executemany("INSERT INTO edges (id, source, target) VALUES (?, ?, ?)", db_rows)
            conn.commit()
            conn.close()
            json_path.write_text(json.dumps(truth_rows), encoding="utf-8")

            run = subprocess.run(
                [str(executable)],
                cwd=project,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=60,
            )
            assert run.returncode == 0, f"Compiled Rust program failed:\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}"
            assert output_path.is_file(), "The compiled Rust program did not create /home/user/stale_edges.txt."
            actual = [line.strip() for line in output_path.read_text(encoding="utf-8").splitlines() if line.strip()]
            assert actual == expected, f"Rust program produced {actual}; expected fixture-derived stale IDs {expected}."

            conn = sqlite3.connect(db_path)
            after_rows = conn.execute("SELECT id, source, target FROM edges ORDER BY id").fetchall()
            conn.close()
            assert after_rows == sorted(db_rows), "The Rust comparison program must not modify the edges table."
        finally:
            for path in paths_to_preserve:
                if path.exists() or path.is_symlink():
                    if path.is_dir() and not path.is_symlink():
                        shutil.rmtree(path)
                    else:
                        path.unlink()
            for path, backup in saved.items():
                os.replace(backup, path)


def split_sql_statements(script):
    statements = []
    start = 0
    state = "normal"
    i = 0
    while i < len(script):
        ch = script[i]
        nxt = script[i + 1] if i + 1 < len(script) else ""
        if state == "normal":
            if ch == "'":
                state = "single"
            elif ch == '"':
                state = "double"
            elif ch == "`":
                state = "backtick"
            elif ch == "[":
                state = "bracket"
            elif ch == "-" and nxt == "-":
                state = "line_comment"
                i += 1
            elif ch == "/" and nxt == "*":
                state = "block_comment"
                i += 1
            elif ch == ";":
                statements.append(script[start:i + 1])
                start = i + 1
        elif state == "single":
            if ch == "'":
                if nxt == "'":
                    i += 1
                else:
                    state = "normal"
        elif state == "double":
            if ch == '"':
                if nxt == '"':
                    i += 1
                else:
                    state = "normal"
        elif state == "backtick":
            if ch == "`":
                if nxt == "`":
                    i += 1
                else:
                    state = "normal"
        elif state == "bracket":
            if ch == "]":
                state = "normal"
        elif state == "line_comment":
            if ch == "\n":
                state = "normal"
        elif state == "block_comment":
            if ch == "*" and nxt == "/":
                state = "normal"
                i += 1
        i += 1

    statements.append(script[start:])
    meaningful = []
    for statement in statements:
        without_comments = re.sub(r"--[^\n]*(?:\n|$)|/\*.*?\*/", " ", statement, flags=re.S).strip()
        if without_comments and without_comments != ";":
            meaningful.append((statement, without_comments))
    return meaningful


def test_optimize_sql_and_db_state():
    sql_path = "/home/user/optimize.sql"
    assert os.path.isfile(sql_path), f"File {sql_path} does not exist."

    with open(sql_path, "r") as f:
        sql_script = f.read()

    statements = split_sql_statements(sql_script)
    assert len(statements) == 2, f"optimize.sql must contain exactly two SQL statements, but found {len(statements)}."
    first = statements[0][1].lstrip()
    second = statements[1][1].lstrip()
    assert re.match(r"(?is)^DELETE\b", first), "The first SQL statement must be a DELETE statement."
    assert re.match(r"(?is)^CREATE\s+INDEX\b", second), "The second SQL statement must be a CREATE INDEX statement."

    db_path = "/home/user/data/graph.db"
    assert os.path.isfile(db_path), f"Database {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Execute the script to apply changes (if not already applied by the student)
    try:
        cursor.executescript(sql_script)
        conn.commit()
    except sqlite3.OperationalError as e:
        # Ignore error if the index already exists (meaning the student ran the script themselves)
        if "already exists" not in str(e).lower():
            pytest.fail(f"Failed to execute optimize.sql: {e}")

    # Check rows remaining in the edges table
    cursor.execute("SELECT id, source, target FROM edges ORDER BY id;")
    rows = cursor.fetchall()

    json_path = "/home/user/data/truth_edges.json"
    with open(json_path, "r") as f:
        truth_data = json.load(f)

    expected_rows = [(item["id"], item["source"], item["target"]) for item in truth_data]
    expected_rows.sort(key=lambda x: x[0])

    assert rows == expected_rows, f"Edges table does not match truth data after applying optimize.sql. Expected {expected_rows}, got {rows}."

    # Check if the index exists and is on the correct columns
    cursor.execute("SELECT count(*) FROM sqlite_master WHERE type='index' AND name='idx_edges_src_tgt';")
    index_count = cursor.fetchone()[0]
    assert index_count == 1, "Index 'idx_edges_src_tgt' does not exist in the database."

    cursor.execute("PRAGMA index_info('idx_edges_src_tgt');")
    index_info = cursor.fetchall()

    # PRAGMA index_info returns rows like: (seqno, cid, name)
    # We need to ensure it covers 'source' then 'target'
    assert len(index_info) == 2, f"Index 'idx_edges_src_tgt' should cover exactly 2 columns, got {len(index_info)}."

    index_columns = [info[2] for info in index_info]
    assert index_columns == ["source", "target"], f"Index 'idx_edges_src_tgt' should be on columns ('source', 'target'), but got {tuple(index_columns)}."

    conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
