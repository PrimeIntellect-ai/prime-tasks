#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
import stat
import subprocess
import pytest

HOME = "/home/user"
DB_PATH = f"{HOME}/data.db"
INTERACTIONS_PATH = f"{HOME}/interactions.json"
SOURCE_PATH = f"{HOME}/process_graph.go"
OUTPUT_PATH = f"{HOME}/output_page2.json"

ORIGINAL_USERS = [
    (1, "Alice", "HR"),
    (2, "Bob", "Engineering"),
    (3, "Charlie", "Engineering"),
    (4, "Diana", "Marketing"),
    (5, "Eve", "Sales"),
    (6, "Frank", "Engineering"),
    (7, "Grace", "Executive"),
    (8, "Heidi", "Engineering"),
    (9, "Ivan", "Sales"),
    (10, "Judy", "HR"),
]

ORIGINAL_INTERACTIONS = [
    {"src": 1, "dst": 2, "weight": 5},
    {"src": 1, "dst": 5, "weight": 6},
    {"src": 2, "dst": 3, "weight": 8},
    {"src": 4, "dst": 2, "weight": 2},
    {"src": 3, "dst": 6, "weight": 10},
    {"src": 4, "dst": 7, "weight": 12},
    {"src": 5, "dst": 10, "weight": 3},
    {"src": 6, "dst": 8, "weight": 1},
    {"src": 7, "dst": 9, "weight": 15},
    {"src": 8, "dst": 9, "weight": 9},
]


def assert_regular_file(path):
    assert os.path.exists(path), f"File not found at {path}"
    mode = os.lstat(path).st_mode
    assert stat.S_ISREG(mode) and not os.path.islink(path), f"{path} must be a regular file"


def load_interactions(path):
    try:
        with open(path, "r") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse interactions JSON file: {e}")


def read_users(path):
    try:
        conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        try:
            return conn.execute(
                "SELECT id, name, department FROM users ORDER BY id"
            ).fetchall()
        finally:
            conn.close()
    except sqlite3.Error as e:
        pytest.fail(f"Failed to query SQLite database: {e}")


def assert_original_fixtures():
    assert_regular_file(DB_PATH)
    assert_regular_file(INTERACTIONS_PATH)
    assert read_users(DB_PATH) == ORIGINAL_USERS, "The users fixture was modified"
    assert load_interactions(INTERACTIONS_PATH) == ORIGINAL_INTERACTIONS, \
        "The interactions fixture was modified"

    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    try:
        objects = conn.execute(
            "SELECT type, name, tbl_name FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"
        ).fetchall()
        assert objects == [("table", "users", "users")], \
            "The database schema was modified"
    finally:
        conn.close()


def expected_page(db_path, interactions_path):
    users = {}
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        try:
            cursor = conn.cursor()
            cursor.execute("SELECT id, name FROM users")
            for row in cursor.fetchall():
                users[row[0]] = {"name": row[1], "centrality": 0}
        finally:
            conn.close()
    except sqlite3.Error as e:
        pytest.fail(f"Failed to query SQLite database: {e}")

    interactions = load_interactions(interactions_path)
    for interaction in interactions:
        src = interaction.get("src")
        dst = interaction.get("dst")
        weight = interaction.get("weight", 0)
        if src in users:
            users[src]["centrality"] += weight
        if dst in users:
            users[dst]["centrality"] += weight

    filtered_users = []
    for uid, data in users.items():
        if data["centrality"] >= 10:
            filtered_users.append({
                "id": uid,
                "name": data["name"],
                "centrality": data["centrality"],
            })
    filtered_users.sort(key=lambda x: (-x["centrality"], x["name"]))
    return filtered_users[3:6]


def remove_output():
    if os.path.lexists(OUTPUT_PATH):
        mode = os.lstat(OUTPUT_PATH).st_mode
        assert not stat.S_ISDIR(mode), f"{OUTPUT_PATH} must not be a directory"
        os.unlink(OUTPUT_PATH)


def run_program():
    assert_regular_file(SOURCE_PATH)
    assert os.path.getsize(SOURCE_PATH) > 0, "process_graph.go is empty"
    remove_output()
    result = subprocess.run(
        ["go", "run", SOURCE_PATH],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, \
        f"process_graph.go failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert_regular_file(OUTPUT_PATH)


def assert_output(expected):
    assert os.path.exists(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH}"
    try:
        with open(OUTPUT_PATH, "r") as f:
            actual_output = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse output JSON file: {e}")

    assert isinstance(actual_output, list), \
        f"Output JSON must be a list, got {type(actual_output).__name__}"
    assert len(actual_output) == len(expected), \
        f"Expected {len(expected)} items in page 2, found {len(actual_output)}"
    for i, (actual, wanted) in enumerate(zip(actual_output, expected)):
        assert actual.get("id") == wanted["id"], \
            f"Item at index {i} has incorrect id. Expected {wanted['id']}, got {actual.get('id')}"
        assert actual.get("name") == wanted["name"], \
            f"Item at index {i} has incorrect name. Expected {wanted['name']}, got {actual.get('name')}"
        assert actual.get("centrality") == wanted["centrality"], \
            f"Item at index {i} has incorrect centrality. Expected {wanted['centrality']}, got {actual.get('centrality')}"


def test_output_page2_json():
    # Reject altered public fixtures, then execute the submitted Go source.
    assert_original_fixtures()
    original_expected = expected_page(DB_PATH, INTERACTIONS_PATH)
    run_program()
    assert_original_fixtures()
    assert_output(original_expected)

    with open(DB_PATH, "rb") as f:
        saved_db = f.read()
    with open(INTERACTIONS_PATH, "rb") as f:
        saved_interactions = f.read()
    with open(OUTPUT_PATH, "rb") as f:
        saved_output = f.read()

    sidecars = {}
    for suffix in ("-wal", "-shm", "-journal"):
        path = DB_PATH + suffix
        if os.path.isfile(path):
            with open(path, "rb") as f:
                sidecars[path] = f.read()
        if os.path.lexists(path):
            os.unlink(path)

    hidden_users = [
        (101, "Zoe", "A"), (102, "Aaron", "B"),
        (103, "Mia", "A"), (104, "Bea", "B"),
        (105, "Carl", "C"), (106, "Dana", "C"),
        (107, "Eli", "D"), (108, "Finn", "D"),
        (109, "Nora", "E"),
    ]
    hidden_interactions = [
        {"src": 101, "dst": 102, "weight": 11},
        {"src": 103, "dst": 104, "weight": 20},
        {"src": 105, "dst": 106, "weight": 15},
        {"src": 107, "dst": 108, "weight": 14},
        {"src": 103, "dst": 105, "weight": 2},
        {"src": 104, "dst": 106, "weight": 1},
        {"src": 107, "dst": 101, "weight": 3},
        {"src": 108, "dst": 102, "weight": 4},
    ]

    try:
        os.unlink(DB_PATH)
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, department TEXT)")
            conn.executemany(
                "INSERT INTO users (id, name, department) VALUES (?, ?, ?)",
                hidden_users,
            )
            conn.commit()
        finally:
            conn.close()
        with open(INTERACTIONS_PATH, "w") as f:
            json.dump(hidden_interactions, f)

        hidden_expected = expected_page(DB_PATH, INTERACTIONS_PATH)
        run_program()
        assert read_users(DB_PATH) == hidden_users, "The program modified the database input"
        assert load_interactions(INTERACTIONS_PATH) == hidden_interactions, \
            "The program modified the interactions input"
        assert_output(hidden_expected)
    finally:
        for suffix in ("", "-wal", "-shm", "-journal"):
            path = DB_PATH + suffix
            if os.path.lexists(path):
                os.unlink(path)
        with open(DB_PATH, "wb") as f:
            f.write(saved_db)
        with open(INTERACTIONS_PATH, "wb") as f:
            f.write(saved_interactions)
        for path, contents in sidecars.items():
            with open(path, "wb") as f:
                f.write(contents)
        remove_output()
        with open(OUTPUT_PATH, "wb") as f:
            f.write(saved_output)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
