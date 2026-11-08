#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import shutil
import sqlite3
import subprocess
import tempfile
import pytest

DB_PATH = "/home/user/compliance.db"
SOURCE_PATH = "/home/user/path_finder.cpp"
BINARY_PATH = "/home/user/path_finder"
OUTPUT_PATH = "/home/user/shortest_path.txt"
EXPECTED_ORIGINAL_PATH = "Mallory,Intern_Group,Staff_Group,Admin_Group,Mainframe"


def execute_query(db_path, query):
    conn = sqlite3.connect(db_path)
    try:
        cursor = conn.cursor()
        cursor.execute(query)
        rows = cursor.fetchall()
        columns = [d[0] for d in cursor.description or []]
        return columns, rows
    finally:
        conn.close()


def create_sql_fixture(path, suffix, base_id):
    conn = sqlite3.connect(path)
    try:
        c = conn.cursor()
        c.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, department TEXT)")
        c.execute("CREATE TABLE groups (id INTEGER PRIMARY KEY, name TEXT)")
        c.execute("CREATE TABLE user_groups (user_id INTEGER, group_id INTEGER)")
        c.execute("CREATE TABLE group_trusts (group_id INTEGER, trusted_group_id INTEGER)")
        c.execute("CREATE TABLE assets (id INTEGER PRIMARY KEY, name TEXT)")
        c.execute("CREATE TABLE group_assets (group_id INTEGER, asset_id INTEGER)")

        users = [
            (base_id + 1, "Reviewer_" + suffix, "Compliance"),
            (base_id + 2, "Auditor_" + suffix, "Compliance"),
            (base_id + 3, "Outsider_" + suffix, "Engineering"),
        ]
        groups = [
            (base_id + 10, "Reviewers_" + suffix),
            (base_id + 20, "Auditors_" + suffix),
            (base_id + 30, "Other_" + suffix),
        ]
        assets = [
            (base_id + 100, "Ledger_" + suffix),
            (base_id + 200, "Archive_" + suffix),
            (base_id + 300, "Secret_" + suffix),
        ]
        c.executemany("INSERT INTO users VALUES (?, ?, ?)", users)
        c.executemany("INSERT INTO groups VALUES (?, ?)", groups)
        c.executemany("INSERT INTO assets VALUES (?, ?)", assets)
        c.executemany("INSERT INTO user_groups VALUES (?, ?)", [
            (base_id + 1, base_id + 10),
            (base_id + 2, base_id + 20),
            (base_id + 3, base_id + 30),
        ])
        c.executemany("INSERT INTO group_assets VALUES (?, ?)", [
            (base_id + 10, base_id + 100),
            (base_id + 20, base_id + 200),
            (base_id + 30, base_id + 300),
        ])
        conn.commit()
    finally:
        conn.close()


def canonical_direct_accesses(db_path):
    conn = sqlite3.connect(db_path)
    try:
        return conn.execute("""
            SELECT u.name, a.name
            FROM users AS u
            JOIN user_groups AS ug ON ug.user_id = u.id
            JOIN groups AS g ON g.id = ug.group_id
            JOIN group_assets AS ga ON ga.group_id = g.id
            JOIN assets AS a ON a.id = ga.asset_id
            WHERE u.department = 'Compliance'
        """).fetchall()
    finally:
        conn.close()


def test_fixed_query_results():
    fixed_query_path = "/home/user/fixed_query.sql"
    assert os.path.exists(fixed_query_path), f"File {fixed_query_path} does not exist."

    with open(fixed_query_path, "r") as f:
        query = f.read().strip()
    assert query, f"{fixed_query_path} is empty."

    try:
        columns, results = execute_query(DB_PATH, query)
    except sqlite3.Error as e:
        pytest.fail(f"Executing fixed_query.sql failed with error: {e}")

    assert len(results) == 2, f"Expected exactly 2 rows, but got {len(results)} rows."
    expected_results = {("Alice", "Audit_Logs"), ("Bob", "Audit_Logs")}
    actual_results = set(results)
    assert actual_results == expected_results, (
        "Query results did not match expected direct accesses for Compliance users. "
        f"Got: {actual_results}"
    )
    assert columns == ["user_name", "asset_name"], (
        f"Expected columns user_name and asset_name, got {columns}"
    )

    # Exercise the submitted query against independent database contents so a
    # constant-returning query cannot satisfy the relational requirement.
    for suffix, base_id in [("North", 1000), ("South", 7000)]:
        fd, fixture_path = tempfile.mkstemp(suffix=".db")
        os.close(fd)
        os.unlink(fixture_path)
        try:
            create_sql_fixture(fixture_path, suffix, base_id)
            expected = canonical_direct_accesses(fixture_path)
            try:
                fixture_columns, actual = execute_query(fixture_path, query)
            except sqlite3.Error as e:
                pytest.fail(f"Corrected query failed on valid schema data: {e}")
            assert fixture_columns == ["user_name", "asset_name"]
            assert sorted(actual) == sorted(expected), (
                f"Query does not implement the required joins on fixture {suffix}: "
                f"expected {expected}, got {actual}"
            )
        finally:
            if os.path.exists(fixture_path):
                os.unlink(fixture_path)


def test_cpp_program_exists():
    assert os.path.isfile(SOURCE_PATH), f"C++ source file {SOURCE_PATH} does not exist."
    assert os.path.getsize(SOURCE_PATH) > 0, f"C++ source file {SOURCE_PATH} is empty."
    assert os.path.isfile(BINARY_PATH), f"Compiled program {BINARY_PATH} does not exist."
    assert os.access(BINARY_PATH, os.X_OK), f"Compiled program {BINARY_PATH} is not executable."


def create_graph_fixture(path, groups, trusts, memberships, asset_group):
    conn = sqlite3.connect(path)
    try:
        c = conn.cursor()
        c.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, department TEXT)")
        c.execute("CREATE TABLE groups (id INTEGER PRIMARY KEY, name TEXT)")
        c.execute("CREATE TABLE user_groups (user_id INTEGER, group_id INTEGER)")
        c.execute("CREATE TABLE group_trusts (group_id INTEGER, trusted_group_id INTEGER)")
        c.execute("CREATE TABLE assets (id INTEGER PRIMARY KEY, name TEXT)")
        c.execute("CREATE TABLE group_assets (group_id INTEGER, asset_id INTEGER)")
        c.executemany("INSERT INTO users VALUES (?, ?, ?)", [
            (501, "Mallory", "Engineering"),
            (502, "SomeoneElse", "Compliance"),
        ])
        c.executemany("INSERT INTO groups VALUES (?, ?)", groups)
        c.executemany("INSERT INTO user_groups VALUES (?, ?)", memberships)
        c.executemany("INSERT INTO group_trusts VALUES (?, ?)", trusts)
        c.executemany("INSERT INTO assets VALUES (?, ?)", [
            (9001, "Mainframe"),
            (9002, "DecoyAsset"),
        ])
        c.execute("INSERT INTO group_assets VALUES (?, ?)", (asset_group, 9001))
        # Add an unrelated asset edge to ensure traversal targets Mainframe.
        c.execute("INSERT INTO group_assets VALUES (?, ?)", (groups[-1][0], 9002))
        conn.commit()
    finally:
        conn.close()


def derive_shortest_path(db_path):
    conn = sqlite3.connect(db_path)
    try:
        edges = collections.defaultdict(list)
        for user_name, group_name in conn.execute("""
            SELECT u.name, g.name FROM user_groups ug
            JOIN users u ON u.id = ug.user_id
            JOIN groups g ON g.id = ug.group_id
        """):
            edges[user_name].append(group_name)
        for group_name, trusted_name in conn.execute("""
            SELECT g.name, tg.name FROM group_trusts gt
            JOIN groups g ON g.id = gt.group_id
            JOIN groups tg ON tg.id = gt.trusted_group_id
        """):
            edges[group_name].append(trusted_name)
        for group_name, asset_name in conn.execute("""
            SELECT g.name, a.name FROM group_assets ga
            JOIN groups g ON g.id = ga.group_id
            JOIN assets a ON a.id = ga.asset_id
        """):
            edges[group_name].append(asset_name)
    finally:
        conn.close()

    queue = collections.deque([("Mallory", ["Mallory"])])
    seen = {"Mallory"}
    while queue:
        node, path = queue.popleft()
        if node == "Mainframe":
            return path
        for nxt in edges[node]:
            if nxt not in seen:
                seen.add(nxt)
                queue.append((nxt, path + [nxt]))
    raise AssertionError("Generated fixture unexpectedly has no Mallory-to-Mainframe path")


def run_program_and_read_output():
    if os.path.exists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)
    result = subprocess.run(
        [BINARY_PATH], cwd="/home/user", capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"path_finder exited with {result.returncode}. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH, "r") as f:
        return f.read().strip()


def test_shortest_path_output():
    # Compile the submitted source and execute that build, rather than trusting
    # a pre-created output file or binary.
    compile_result = subprocess.run(
        ["g++", "-std=c++17", SOURCE_PATH, "-lsqlite3", "-o", BINARY_PATH],
        capture_output=True, text=True, timeout=30
    )
    assert compile_result.returncode == 0, (
        f"Compiling path_finder.cpp failed: {compile_result.stderr}"
    )

    content = run_program_and_read_output()
    assert content == EXPECTED_ORIGINAL_PATH, (
        f"Shortest path output is incorrect. Expected '{EXPECTED_ORIGINAL_PATH}', "
        f"but got '{content}'."
    )

    backup_fd, backup_path = tempfile.mkstemp(suffix=".db")
    os.close(backup_fd)
    shutil.copy2(DB_PATH, backup_path)
    fixtures = [
        (
            [(610, "Entry_North"), (620, "Bridge_North"), (630, "Vault_North"), (640, "Noise_North")],
            [(610, 620), (620, 630)],
            [(501, 610), (502, 640)],
            630,
        ),
        (
            [(710, "Start_West"), (720, "Middle_West"), (730, "Noise_West")],
            [(710, 720)],
            [(501, 710), (502, 730)],
            720,
        ),
    ]
    try:
        for groups, trusts, memberships, asset_group in fixtures:
            if os.path.exists(DB_PATH):
                os.unlink(DB_PATH)
            create_graph_fixture(DB_PATH, groups, trusts, memberships, asset_group)
            expected = ",".join(derive_shortest_path(DB_PATH))
            actual = run_program_and_read_output()
            assert actual == expected, (
                f"Program did not compute the graph path from database contents. "
                f"Expected {expected!r}, got {actual!r}"
            )
    finally:
        shutil.copy2(backup_path, DB_PATH)
        os.unlink(backup_path)
        # Leave the required output in its correct state for the original DB.
        restored = run_program_and_read_output()
        assert restored == EXPECTED_ORIGINAL_PATH
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
