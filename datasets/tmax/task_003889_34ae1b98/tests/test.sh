#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

DB_PATH = '/home/user/graph.db'
SCRIPT_PATH = '/home/user/extract_patterns.py'
OUTPUT_PATH = '/home/user/triangles.json'


def get_expected_triangles(db_path):
    """Dynamically compute the expected triangles from the database."""
    conn = sqlite3.connect(db_path)
    try:
        c = conn.cursor()
        c.execute('''
            SELECT a.src, b.src, c.src
            FROM entity_links a
            JOIN entity_links b ON a.dst = b.src
            JOIN entity_links c ON b.dst = c.src AND c.dst = a.src
            WHERE a.rel = 'friend' AND b.rel = 'friend' AND c.rel = 'friend'
        ''')
        triangles = {tuple(sorted(row)) for row in c.fetchall()}
        return sorted([list(t) for t in triangles])
    finally:
        conn.close()


def load_and_check_output(expected):
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."
    assert os.path.isfile(OUTPUT_PATH), f"Path {OUTPUT_PATH} is not a file."

    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} does not contain valid JSON.")

    assert isinstance(data, list), "Outer JSON structure must be a list."
    for item in data:
        assert isinstance(item, list), "Inner elements must be lists."
        assert all(isinstance(x, int) for x in item), "Inner list elements must be integers."

    assert data == expected, \
        f"JSON content does not match expected output. Expected {expected}, got {data}."


def install_database(edges):
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('CREATE TABLE entity_links (src INT, dst INT, rel VARCHAR(50))')
        conn.executemany('INSERT INTO entity_links VALUES (?, ?, ?)', edges)
        conn.commit()
    finally:
        conn.close()


def run_submission():
    if os.path.lexists(OUTPUT_PATH):
        if os.path.isdir(OUTPUT_PATH) and not os.path.islink(OUTPUT_PATH):
            shutil.rmtree(OUTPUT_PATH)
        else:
            os.remove(OUTPUT_PATH)

    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, \
        f"Script execution failed with code {result.returncode}. stderr: {result.stderr}"


def random_distinct_ids(count):
    values = set()
    while len(values) < count:
        values.add(secrets.randbelow(900000000) + 10000000)
    return list(values)


def test_final_state_and_executable_etl():
    # Preserve the original verifier's existence and submitted-output checks.
    assert os.path.exists(SCRIPT_PATH), f"Script file {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file."
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."
    assert os.path.isfile(OUTPUT_PATH), f"Path {OUTPUT_PATH} is not a file."

    original_expected = get_expected_triangles(DB_PATH)
    load_and_check_output(original_expected)

    fd, backup_path = tempfile.mkstemp(prefix='graph-backup-', suffix='.db')
    os.close(fd)
    shutil.copyfile(DB_PATH, backup_path)

    try:
        # Exercise the submitted script on runtime-generated databases so a
        # fixed or independently hardcoded triangles.json cannot pass.
        a, b, c, d, e, f, g, h, i = random_distinct_ids(9)
        cases = [
            [
                (a, b, 'friend'), (b, c, 'friend'), (c, a, 'friend'),
                (d, e, 'friend'), (e, f, 'friend'), (f, d, 'friend'),
                (a, b, 'friend'),  # duplicate must not duplicate a triangle
                (g, h, 'follower'), (h, i, 'follower'), (i, g, 'follower'),
                (a, d, 'friend'), (e, c, 'blocks'), (g, a, 'friend'),
            ],
            [
                (a, b, 'friend'), (b, c, 'friend'), (c, a, 'follower'),
                (d, e, 'friend'), (e, f, 'blocks'), (f, d, 'friend'),
                (g, h, 'follower'), (h, i, 'follower'), (i, g, 'follower'),
            ],
        ]

        for edges in cases:
            install_database(edges)
            expected = get_expected_triangles(DB_PATH)
            run_submission()
            load_and_check_output(expected)
    finally:
        shutil.copyfile(backup_path, DB_PATH)
        os.remove(backup_path)

    # Execute the artifact against the real database and require it to leave
    # the requested final output in place.
    run_submission()
    load_and_check_output(get_expected_triangles(DB_PATH))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
