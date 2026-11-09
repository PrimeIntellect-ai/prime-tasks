#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import sqlite3
import pytest

REACH_FILE = '/home/user/reach.txt'
SQL_FILE = '/home/user/indexes.sql'
DB_PATH = '/home/user/network.db'

def test_reach_value():
    assert os.path.exists(REACH_FILE), f"The file {REACH_FILE} does not exist."
    with open(REACH_FILE, 'r') as f:
        content = f.read().strip()

    try:
        reach_val = float(content)
    except ValueError:
        pytest.fail(f"The content of {REACH_FILE} could not be parsed as a float. Found: '{content}'")

    assert reach_val == 4.5, f"Expected Extended Reach to be 4.5, but got {reach_val}."

def test_sql_file_exists_and_contains_create_index():
    assert os.path.exists(SQL_FILE), f"The file {SQL_FILE} does not exist."
    with open(SQL_FILE, 'r') as f:
        content = f.read().lower()

    assert "create " in content and "index " in content, f"{SQL_FILE} does not seem to contain CREATE INDEX statements."
    assert "follows" in content, f"{SQL_FILE} does not seem to reference the 'follows' table."

def _quoted_identifier(value):
    return '"' + value.replace('"', '""') + '"'

def _user_indexes(conn, table):
    result = {}
    for row in conn.execute(f"PRAGMA index_list({_quoted_identifier(table)})"):
        # PRAGMA index_list: seq, name, unique, origin, partial
        name = row[1]
        partial = bool(row[4]) if len(row) > 4 else False
        if name.startswith('sqlite_autoindex_'):
            continue
        columns = tuple(
            info[2] for info in conn.execute(
                f"PRAGMA index_info({_quoted_identifier(name)})"
            )
        )
        result[name] = (columns, partial)
    return result

def _indexes_created_by_sql_file():
    with open(SQL_FILE, 'r') as f:
        sql = f.read()

    # indexes.sql is required to contain the actual CREATE INDEX statements,
    # rather than unrelated executable SQL padded with index-related words.
    without_comments = re.sub(r'/\*.*?\*/', '', sql, flags=re.S)
    without_comments = re.sub(r'--[^\n]*', '', without_comments)
    statements = [part.strip() for part in without_comments.split(';') if part.strip()]
    assert statements, f"{SQL_FILE} contains no SQL statements."
    for statement in statements:
        assert re.match(r'^CREATE\s+(?:UNIQUE\s+)?INDEX\b', statement, re.I), (
            f"{SQL_FILE} must contain CREATE INDEX statements; found: {statement!r}"
        )

    conn = sqlite3.connect(':memory:')
    try:
        conn.executescript('''
            CREATE TABLE users (
                user_id INTEGER PRIMARY KEY,
                username TEXT UNIQUE NOT NULL
            );
            CREATE TABLE follows (
                follower_id INTEGER NOT NULL,
                followee_id INTEGER NOT NULL,
                PRIMARY KEY (follower_id, followee_id)
            );
        ''')
        conn.executescript(sql)
        return _user_indexes(conn, 'follows')
    except sqlite3.Error as exc:
        pytest.fail(f"The SQL in {SQL_FILE} is not valid against the supplied schema: {exc}")
    finally:
        conn.close()

def test_database_has_new_indexes():
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Query for user-created indexes on the 'follows' table
    cursor.execute("""
        SELECT name, sql 
        FROM sqlite_master 
        WHERE type='index' 
          AND tbl_name='follows' 
          AND sql IS NOT NULL
    """)
    indexes = cursor.fetchall()

    # Filter out auto-indexes just in case, though they usually have sql IS NULL or start with sqlite_autoindex
    user_created_indexes = [idx for idx in indexes if not idx[0].startswith('sqlite_autoindex_')]

    assert len(user_created_indexes) > 0, "No new user-created indexes found on the 'follows' table in the database."

    actual_indexes = _user_indexes(conn, 'follows')
    declared_indexes = _indexes_created_by_sql_file()

    # The primary-key auto-index already begins with follower_id. The missing
    # access path used by both direct- and level-2-follower lookups is by
    # followee_id, so a useful non-partial index must lead with that column.
    useful_declared = {
        name: definition
        for name, definition in declared_indexes.items()
        if definition[0] and definition[0][0].lower() == 'followee_id' and not definition[1]
    }
    assert useful_declared, (
        f"{SQL_FILE} does not create a non-partial index on follows whose leading column is followee_id."
    )

    matching = [
        name for name, definition in useful_declared.items()
        if name in actual_indexes and actual_indexes[name] == definition
    ]
    assert matching, (
        "A useful follows(followee_id, ...) index declared in indexes.sql was not actually created in network.db."
    )

    conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
