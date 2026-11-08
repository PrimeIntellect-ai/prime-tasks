#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3
import subprocess
import secrets
import pytest

DB_PATH = "/home/user/warehouse.db"
C_FILE = "/home/user/etl_extract.c"
BIN_FILE = "/home/user/etl_extract"
OUT_FILE = "/home/user/output.json"


def get_expected_data(limit, offset):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    query = """
        SELECT a.id as article_id, a.title, au.name as author_name, a.views
        FROM articles a
        JOIN authors au ON a.author_id = au.id
        JOIN tags t ON a.id = t.article_id
        WHERE t.tag_name = 'AI' AND au.reputation > 100
        ORDER BY a.views DESC
        LIMIT ? OFFSET ?
    """
    cur.execute(query, (limit, offset))
    rows = cur.fetchall()
    conn.close()
    return [dict(r) for r in rows]


def load_and_validate_output(expected_data):
    assert os.path.isfile(OUT_FILE), f"Output file {OUT_FILE} is missing."

    with open(OUT_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {OUT_FILE} as JSON: {e}")

    assert isinstance(data, list), "JSON root must be an array."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items, got {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not an object."

        assert "article_id" in actual, f"Missing 'article_id' in item {i}"
        assert isinstance(actual["article_id"], int), f"'article_id' in item {i} must be an integer"

        assert "title" in actual, f"Missing 'title' in item {i}"
        assert isinstance(actual["title"], str), f"'title' in item {i} must be a string"

        assert "author_name" in actual, f"Missing 'author_name' in item {i}"
        assert isinstance(actual["author_name"], str), f"'author_name' in item {i} must be a string"

        assert "views" in actual, f"Missing 'views' in item {i}"
        assert isinstance(actual["views"], int), f"'views' in item {i} must be an integer"

        assert actual["article_id"] == expected["article_id"], f"Incorrect article_id at index {i}"
        assert actual["title"] == expected["title"], f"Incorrect title at index {i}"
        assert actual["author_name"] == expected["author_name"], f"Incorrect author_name at index {i}"
        assert actual["views"] == expected["views"], f"Incorrect views at index {i}"


def run_binary(limit, offset):
    if os.path.exists(OUT_FILE):
        os.remove(OUT_FILE)

    try:
        result = subprocess.run(
            [BIN_FILE, str(limit), str(offset)],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except Exception as e:
        pytest.fail(f"Failed to execute {BIN_FILE}: {e}")

    assert result.returncode == 0, (
        f"Binary execution failed with return code {result.returncode}. "
        f"Stderr: {result.stderr}"
    )
    assert not result.stdout.strip(), "Program should not output anything to standard output."
    assert os.path.isfile(OUT_FILE), f"Output file {OUT_FILE} was not created by the program."


def test_files_exist():
    assert os.path.isfile(C_FILE), f"Source file {C_FILE} is missing."
    assert os.path.isfile(BIN_FILE), f"Compiled binary {BIN_FILE} is missing."
    assert os.access(BIN_FILE, os.X_OK), f"{BIN_FILE} is not executable."


def test_execution_and_output():
    run_binary(3, 1)


def test_json_contents():
    load_and_validate_output(get_expected_data(3, 1))


def test_dynamic_database_and_pagination():
    token = secrets.token_hex(8)
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    occupied_authors = {row[0] for row in cur.execute("SELECT id FROM authors")}
    occupied_articles = {row[0] for row in cur.execute("SELECT id FROM articles")}

    def fresh_id(occupied):
        while True:
            candidate = 10000 + secrets.randbelow(1000000000)
            if candidate not in occupied:
                occupied.add(candidate)
                return candidate

    good_author = fresh_id(occupied_authors)
    low_rep_author = fresh_id(occupied_authors)
    cur.execute(
        "INSERT INTO authors(id, name, reputation) VALUES (?, ?, ?)",
        (good_author, "Dynamic Author " + token, 101 + secrets.randbelow(500)),
    )
    cur.execute(
        "INSERT INTO authors(id, name, reputation) VALUES (?, ?, ?)",
        (low_rep_author, "Low Reputation " + token, 100),
    )

    base_views = 2000000 + secrets.randbelow(100000)
    for i in range(7):
        article_id = fresh_id(occupied_articles)
        cur.execute(
            "INSERT INTO articles(id, author_id, title, views) VALUES (?, ?, ?, ?)",
            (article_id, good_author, f"Dynamic AI Article {token} {i}", base_views + i * 1000),
        )
        cur.execute(
            "INSERT INTO tags(article_id, tag_name) VALUES (?, ?)",
            (article_id, "AI"),
        )

    low_rep_article = fresh_id(occupied_articles)
    cur.execute(
        "INSERT INTO articles(id, author_id, title, views) VALUES (?, ?, ?, ?)",
        (low_rep_article, low_rep_author, "Excluded Low Reputation " + token, base_views + 20000),
    )
    cur.execute("INSERT INTO tags(article_id, tag_name) VALUES (?, 'AI')", (low_rep_article,))

    wrong_tag_article = fresh_id(occupied_articles)
    cur.execute(
        "INSERT INTO articles(id, author_id, title, views) VALUES (?, ?, ?, ?)",
        (wrong_tag_article, good_author, "Excluded Wrong Tag " + token, base_views + 19000),
    )
    cur.execute("INSERT INTO tags(article_id, tag_name) VALUES (?, 'AIML')", (wrong_tag_article,))

    conn.commit()
    conn.close()

    cases = set()
    while len(cases) < 5:
        cases.add((1 + secrets.randbelow(6), secrets.randbelow(13)))

    for limit, offset in cases:
        expected = get_expected_data(limit, offset)
        run_binary(limit, offset)
        load_and_validate_output(expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
