#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import sqlite3
import subprocess
from collections import deque

DB_PATH = '/home/user/research_data.db'
SCRIPT_PATH = '/home/user/find_path.py'
RESULT_PATH = '/home/user/result.txt'
INDEXES_SQL_PATH = '/home/user/indexes.sql'


def shortest_path_in_db():
    conn = sqlite3.connect(DB_PATH)
    try:
        alpha = conn.execute("SELECT id FROM artifacts WHERE name = 'Alpha'").fetchone()
        omega = conn.execute("SELECT id FROM artifacts WHERE name = 'Omega'").fetchone()
        assert alpha is not None and omega is not None, "Alpha or Omega is missing."
        start, target = alpha[0], omega[0]
        adjacency = {}
        for source, dest in conn.execute('SELECT source_id, target_id FROM relationships'):
            adjacency.setdefault(source, []).append(dest)
    finally:
        conn.close()

    queue = deque([(start, 0)])
    seen = {start}
    while queue:
        node, depth = queue.popleft()
        if node == target:
            return depth
        for neighbor in adjacency.get(node, ()):
            if neighbor not in seen:
                seen.add(neighbor)
                queue.append((neighbor, depth + 1))
    return None


def run_submission():
    assert os.path.isfile(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist or is not a regular file."
    assert not os.path.islink(SCRIPT_PATH), f"{SCRIPT_PATH} must not be a symbolic link."
    if os.path.lexists(RESULT_PATH):
        os.unlink(RESULT_PATH)
    completed = subprocess.run(
        ['python3', SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"{SCRIPT_PATH} exited with status {completed.returncode}. "
        f"stdout: {completed.stdout!r}; stderr: {completed.stderr!r}"
    )
    assert os.path.isfile(RESULT_PATH), f"Running {SCRIPT_PATH} did not create {RESULT_PATH}."
    with open(RESULT_PATH, 'r') as f:
        content = f.read().strip()
    assert re.fullmatch(r'-?\d+', content), f"Expected a single integer, got {content!r}."
    return int(content)


def test_result_txt_content():
    expected = shortest_path_in_db()
    assert expected is not None, "The supplied database has no path from Alpha to Omega."
    actual = run_submission()
    assert actual == expected, f"Script returned {actual}, but the shortest path is {expected}."

    assert os.path.exists(RESULT_PATH), f"File {RESULT_PATH} does not exist."
    with open(RESULT_PATH, 'r') as f:
        content = f.read().strip()
    assert content == "6", f"Expected {RESULT_PATH} to contain exactly '6', but got '{content}'."


def test_indexes_sql_content():
    assert os.path.exists(INDEXES_SQL_PATH), f"File {INDEXES_SQL_PATH} does not exist."
    assert os.path.isfile(INDEXES_SQL_PATH), f"{INDEXES_SQL_PATH} is not a regular file."
    with open(INDEXES_SQL_PATH, 'r') as f:
        original_content = f.read()
    content = original_content.lower()

    assert "create index" in content, f"{INDEXES_SQL_PATH} does not contain a 'CREATE INDEX' statement."
    assert "relationships" in content, f"{INDEXES_SQL_PATH} does not mention the 'relationships' table."
    assert "source_id" in content, f"{INDEXES_SQL_PATH} does not mention the 'source_id' column."

    # Execute the submitted SQL against a clean schema, rather than trusting keywords.
    check = sqlite3.connect(':memory:')
    try:
        check.execute('CREATE TABLE relationships (source_id INTEGER, target_id INTEGER)')
        check.executescript(original_content)
        created = check.execute("PRAGMA index_list('relationships')").fetchall()
        qualifying_names = []
        for idx in created:
            name = idx[1]
            escaped = name.replace("'", "''")
            columns = check.execute(f"PRAGMA index_info('{escaped}')").fetchall()
            if columns and columns[0][2] == 'source_id':
                qualifying_names.append(name)
        assert qualifying_names, (
            f"Executing {INDEXES_SQL_PATH} did not create an index on relationships "
            "whose first column is source_id."
        )
    finally:
        check.close()

    # At least one qualifying statement saved in indexes.sql must also have been
    # executed against the real database.
    real = sqlite3.connect(DB_PATH)
    try:
        actual_names = {row[1] for row in real.execute("PRAGMA index_list('relationships')")}
    finally:
        real.close()
    assert actual_names.intersection(qualifying_names), (
        "The qualifying index described by indexes.sql was not created in the database."
    )


def test_database_index_created():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("PRAGMA index_list('relationships')")
    indexes = cursor.fetchall()

    assert len(indexes) > 0, "No indexes were found on the 'relationships' table in the database."

    valid_index_found = False
    for idx in indexes:
        index_name = idx[1]
        escaped = index_name.replace("'", "''")
        cursor.execute(f"PRAGMA index_info('{escaped}')")
        columns = cursor.fetchall()
        if columns and columns[0][2] == 'source_id':
            valid_index_found = True
            break

    assert valid_index_found, "No index found on the 'relationships' table that starts with the 'source_id' column."
    conn.close()


def test_script_on_unseen_graph():
    # Replace only the edge set temporarily with a runtime-generated graph. This
    # catches scripts that merely write the known answer instead of traversing.
    conn = sqlite3.connect(DB_PATH)
    original_edges = conn.execute('SELECT source_id, target_id FROM relationships').fetchall()
    original_result = None
    if os.path.exists(RESULT_PATH):
        with open(RESULT_PATH, 'rb') as f:
            original_result = f.read()

    rng = random.SystemRandom()
    length = rng.choice([2, 3, 4, 5, 7])
    available = list(range(2, 1000))
    chosen = rng.sample(available, (length - 1) + 4)
    middle = chosen[:length - 1]
    dead = chosen[length - 1:]
    path = [1] + middle + [1000]
    edges = list(zip(path, path[1:]))
    for node in dead:
        edges.extend([(1, node), (node, node)])

    try:
        conn.execute('DELETE FROM relationships')
        conn.executemany('INSERT INTO relationships(source_id, target_id) VALUES (?, ?)', edges)
        conn.commit()
        expected = shortest_path_in_db()
        assert expected == length
        actual = run_submission()
        assert actual == expected, (
            f"On a runtime-generated graph, script returned {actual}; expected {expected}."
        )
    finally:
        conn.execute('DELETE FROM relationships')
        conn.executemany('INSERT INTO relationships(source_id, target_id) VALUES (?, ?)', original_edges)
        conn.commit()
        conn.close()
        if original_result is None:
            if os.path.lexists(RESULT_PATH):
                os.unlink(RESULT_PATH)
        else:
            with open(RESULT_PATH, 'wb') as f:
                f.write(original_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
