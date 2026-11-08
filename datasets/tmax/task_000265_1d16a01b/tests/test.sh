#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import sqlite3
import subprocess

import pytest

SCRIPT_PATH = '/home/user/etl_pipeline.py'
JSON_PATH = '/home/user/influencer_metrics.json'
DB_PATH = '/home/user/social_data.db'


def run_pipeline():
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'Pipeline exited with status {result.returncode}. '
        f'stdout: {result.stdout!r}; stderr: {result.stderr!r}'
    )
    assert os.path.isfile(JSON_PATH), f'Pipeline did not create {JSON_PATH}'


@pytest.fixture(scope='module')
def original_run():
    assert os.path.isfile(SCRIPT_PATH), f'Pipeline script missing at {SCRIPT_PATH}'
    run_pipeline()


def test_script_exists_and_is_python(original_run):
    assert os.path.isfile(SCRIPT_PATH), f'Pipeline script missing at {SCRIPT_PATH}'
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    compile(source, SCRIPT_PATH, 'exec')


def test_json_file_exists(original_run):
    """Test that the output JSON file exists."""
    assert os.path.isfile(JSON_PATH), f"Output file missing at {JSON_PATH}"


def test_json_contents_correct(original_run):
    """Test that the JSON file contains the correct data and sorting."""
    with open(JSON_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File at {JSON_PATH} is not valid JSON")

    assert isinstance(data, list), "JSON root must be a list of dictionaries"

    expected_data = [
        {"user_id": 4, "name": "Diana", "degree": 3, "total_engagements": 150},
        {"user_id": 3, "name": "Charlie", "degree": 2, "total_engagements": 75},
        {"user_id": 1, "name": "Alice", "degree": 3, "total_engagements": 45},
        {"user_id": 2, "name": "Bob", "degree": 2, "total_engagements": 7},
        {"user_id": 6, "name": "Frank", "degree": 2, "total_engagements": 3}
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, found {len(data)}"

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a dictionary"
        expected_keys = {"user_id", "name", "degree", "total_engagements"}
        assert set(actual.keys()) == expected_keys, f"Item at index {i} has incorrect keys. Expected {expected_keys}, found {set(actual.keys())}"
        assert actual["user_id"] == expected["user_id"], f"Item at index {i} has wrong user_id. Expected {expected['user_id']}, got {actual['user_id']}"
        assert actual["name"] == expected["name"], f"Item at index {i} has wrong name. Expected '{expected['name']}', got '{actual['name']}'"
        assert actual["degree"] == expected["degree"], f"Item at index {i} has wrong degree. Expected {expected['degree']}, got {actual['degree']}"
        assert actual["total_engagements"] == expected["total_engagements"], f"Item at index {i} has wrong total_engagements. Expected {expected['total_engagements']}, got {actual['total_engagements']}"


def test_pipeline_on_unseen_database(original_run):
    # Build an unseen fixture so a script that merely writes the known JSON cannot pass.
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    ids = secrets.SystemRandom().sample(range(100, 10000), 7)
    token = secrets.token_hex(4)
    users = [(uid, f'User_{i}_{token}') for i, uid in enumerate(ids)]
    a, b, c, d, e, f, g = ids

    friendships = [
        (a, b), (a, c), (a, d), (b, c),
        (d, e), (d, f), (f, g),
        (a, b),       # duplicate must not increase degree
        (c, a),       # reversed duplicate must not increase degree
    ]

    base_post = secrets.randbelow(50000) + 1000
    posts = [
        (base_post + 1, a, 'a1'),
        (base_post + 2, a, 'a2 without engagement'),
        (base_post + 3, b, 'b without engagement'),
        (base_post + 4, c, 'c1'),
        (base_post + 5, d, 'd1'),
        (base_post + 6, d, 'd2'),
        (base_post + 7, e, 'excluded low-degree user'),
        (base_post + 8, g, 'excluded low-degree user'),
    ]

    tie_total = secrets.randbelow(300) + 200
    a_total = secrets.randbelow(80) + 20
    first_d = tie_total // 2
    engagements = [
        (base_post + 1, a_total - 3, 3),
        (base_post + 4, tie_total - 11, 11),
        (base_post + 5, first_d, 0),
        (base_post + 6, tie_total - first_d - 5, 5),
        (base_post + 7, 900, 100),
        (base_post + 8, 800, 100),
    ]

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute('CREATE TABLE users (user_id INTEGER PRIMARY KEY, name TEXT)')
    cur.execute('CREATE TABLE friendships (user_id1 INTEGER, user_id2 INTEGER)')
    cur.execute('CREATE TABLE posts (post_id INTEGER PRIMARY KEY, user_id INTEGER, content TEXT)')
    cur.execute('CREATE TABLE engagements (post_id INTEGER PRIMARY KEY, likes INTEGER, shares INTEGER)')
    cur.executemany('INSERT INTO users VALUES (?, ?)', users)
    cur.executemany('INSERT INTO friendships VALUES (?, ?)', friendships)
    cur.executemany('INSERT INTO posts VALUES (?, ?, ?)', posts)
    cur.executemany('INSERT INTO engagements VALUES (?, ?, ?)', engagements)
    conn.commit()

    # Independently derive the oracle from the fixture before executing the submission.
    names = dict(cur.execute('SELECT user_id, name FROM users'))
    neighbors = {uid: set() for uid in names}
    for left, right in cur.execute('SELECT user_id1, user_id2 FROM friendships'):
        neighbors[left].add(right)
        neighbors[right].add(left)

    totals = {uid: 0 for uid in names}
    rows = cur.execute('''
        SELECT p.user_id, e.likes, e.shares
        FROM posts AS p
        LEFT JOIN engagements AS e ON e.post_id = p.post_id
    ''').fetchall()
    for uid, likes, shares in rows:
        totals[uid] += (likes or 0) + (shares or 0)
    conn.close()

    expected = [
        {
            'user_id': uid,
            'name': names[uid],
            'degree': len(neighbors[uid]),
            'total_engagements': totals[uid],
        }
        for uid in names
        if len(neighbors[uid]) >= 2
    ]
    expected.sort(key=lambda row: (-row['total_engagements'], row['user_id']))

    run_pipeline()
    with open(JSON_PATH, 'r', encoding='utf-8') as fobj:
        try:
            actual = json.load(fobj)
        except json.JSONDecodeError:
            pytest.fail(f'File at {JSON_PATH} is not valid JSON')

    assert actual == expected, f'Pipeline output for unseen database was incorrect. Expected {expected}, got {actual}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
