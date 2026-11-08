#!/bin/bash
mkdir -p /logs/verifier

if (
    set -e

    # The submitted artifact must be an actual executable, not an empty placeholder.
    test -f /home/user/graph_diag
    test -x /home/user/graph_diag
    python3 - <<'PY'
with open('/home/user/graph_diag', 'rb') as f:
    assert f.read(4) == b'\x7fELF', 'graph_diag is not an ELF executable'
PY

    # Execute the submitted binary from a clean state and require it to produce
    # every runtime artifact itself.
    rm -f /home/user/graph.db /home/user/graph.db-shm /home/user/graph.db-wal \
          /home/user/graph.db-journal /home/user/traversal.log /home/user/deadlock.log
    timeout 20s /home/user/graph_diag
    test -f /home/user/graph.db
    test -f /home/user/traversal.log
    test -f /home/user/deadlock.log

    # Independently compile and run the submitted source so a fabricated binary
    # cannot conceal nonfunctional source.
    g++ -std=c++11 -pthread /home/user/graph_diag.cpp -lsqlite3 -o /tmp/graph_diag_rebuilt
    rm -f /home/user/graph.db /home/user/graph.db-shm /home/user/graph.db-wal \
          /home/user/graph.db-journal /home/user/traversal.log /home/user/deadlock.log
    timeout 20s /tmp/graph_diag_rebuilt

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3


def test_files_exist():
    """Verify that all required files have been created."""
    expected_files = [
        '/home/user/graph_diag.cpp',
        '/home/user/graph_diag',
        '/home/user/graph.db',
        '/home/user/traversal.log',
        '/home/user/deadlock.log'
    ]
    for filepath in expected_files:
        assert os.path.isfile(filepath), f"Expected file {filepath} does not exist."

    assert os.access('/home/user/graph_diag', os.X_OK), "graph_diag is not executable"
    with open('/home/user/graph_diag', 'rb') as f:
        assert f.read(4) == b'\x7fELF', "graph_diag is not an ELF executable"


def test_database_schema_and_data():
    """Verify the program created the requested schema and inserted the graph."""
    conn = sqlite3.connect('/home/user/graph.db')
    try:
        nodes_info = conn.execute('PRAGMA table_info(nodes)').fetchall()
        edges_info = conn.execute('PRAGMA table_info(edges)').fetchall()
        assert [(r[1], r[2].upper()) for r in nodes_info] == [
            ('id', 'TEXT'), ('props', 'TEXT')
        ]
        assert nodes_info[0][5] == 1, "nodes.id is not the primary key"
        assert [(r[1], r[2].upper()) for r in edges_info] == [
            ('source', 'TEXT'), ('target', 'TEXT'), ('rel_type', 'TEXT')
        ]

        node_ids = {r[0] for r in conn.execute('SELECT id FROM nodes')}
        assert {'A', 'B', 'C', 'D'} <= node_ids

        edges = set(conn.execute(
            'SELECT source, target, rel_type FROM edges'
        ).fetchall())
        assert {
            ('A', 'B', 'DEPENDS_ON'),
            ('B', 'C', 'DEPENDS_ON'),
            ('C', 'D', 'DEPENDS_ON'),
            ('A', 'D', 'DEPENDS_ON'),
        } <= edges
    finally:
        conn.close()


def test_database_index():
    """Verify that the required composite traversal index was created."""
    db_path = '/home/user/graph.db'
    assert os.path.exists(db_path), f"Database file {db_path} not found."

    conn = sqlite3.connect(db_path)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name, sql FROM sqlite_master WHERE type='index' AND name='idx_graph_traversal';")
        row = cursor.fetchone()
        assert row is not None, "Index 'idx_graph_traversal' does not exist in the database."

        sql = row[1].lower() if row[1] else ""
        assert "edges" in sql, "Index 'idx_graph_traversal' does not seem to be on the 'edges' table."

        columns = [r[2].lower() for r in conn.execute(
            "PRAGMA index_info('idx_graph_traversal')"
        )]
        assert len(columns) >= 2, "idx_graph_traversal is not a composite index"
        assert columns[0] == 'source', "Traversal index must begin with source"
    finally:
        conn.close()


def test_traversal_log():
    """Verify traversal.log contains the nodes reachable from A in the database."""
    log_path = '/home/user/traversal.log'
    assert os.path.exists(log_path), f"Log file {log_path} not found."

    with open(log_path, 'r') as f:
        content = f.read().splitlines()
    nodes = {line.strip() for line in content if line.strip()}

    assert 'B' in nodes, "'B' is missing from traversal.log"
    assert 'C' in nodes, "'C' is missing from traversal.log"
    assert 'D' in nodes, "'D' is missing from traversal.log"

    conn = sqlite3.connect('/home/user/graph.db')
    try:
        expected = {
            row[0] for row in conn.execute('''
                WITH RECURSIVE reachable(id) AS (
                    SELECT target FROM edges WHERE source = ?
                    UNION
                    SELECT e.target
                    FROM edges e JOIN reachable r ON e.source = r.id
                )
                SELECT id FROM reachable
            ''', ('A',))
        }
    finally:
        conn.close()
    assert expected <= nodes, "traversal.log omits nodes reachable from A"


def test_deadlock_log():
    """Verify that deadlock.log contains the required detection marker."""
    log_path = '/home/user/deadlock.log'
    assert os.path.exists(log_path), f"Log file {log_path} not found."
    with open(log_path, 'r') as f:
        content = f.read()
    assert 'DEADLOCK_DETECTED' in content, "The string 'DEADLOCK_DETECTED' was not found in deadlock.log"
    assert content.strip() == 'DEADLOCK_DETECTED', "deadlock.log does not contain the exact required marker"


def test_required_cpp_implementation_present():
    """Check that the rebuilt source contains the required SQLite and threading mechanisms."""
    cpp_path = '/home/user/graph_diag.cpp'
    assert os.path.exists(cpp_path), f"Source file {cpp_path} not found."
    with open(cpp_path, 'r') as f:
        content = f.read()

    assert 'sqlite3_bind' in content, "The source code does not appear to use 'sqlite3_bind' for parameterization."
    assert 'sqlite3_prepare_v2' in content, "sqlite3_prepare_v2 is not used"
    assert re.search(r'WITH\s+RECURSIVE', content, re.I), "No recursive CTE was found"
    assert re.search(r'std::thread\s*[<(]', content), "std::thread is not used"
    assert 'SQLITE_BUSY' in content, "SQLITE_BUSY is not handled"
    assert re.search(r'sleep_for\s*\(', content), "The thread delay is not implemented"
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
