#!/bin/bash
set -u
mkdir -p /logs/verifier

run_verifier() {
    test -f /home/user/analyze.go || return 1
    test -f /home/user/network.db || return 1

    # Verify that the supplied database still contains the original data before
    # executing any student code.
    python3 - <<'PY' || return 1
import sqlite3

path = '/home/user/network.db'
expected_nodes = [
    ('N01', 'Engineering'), ('N02', 'Engineering'),
    ('N03', 'Engineering'), ('N04', 'Engineering'),
    ('N05', 'Engineering'), ('N06', 'Sales'),
    ('N07', 'Sales'), ('N08', 'Sales'), ('N09', 'Sales'),
    ('N10', 'Marketing'), ('N11', 'Marketing'),
    ('N12', 'Marketing'),
]
expected_edges = [
    ('N01', 'N02', 100), ('N01', 'N02', 200),
    ('N02', 'N03', 150), ('N03', 'N01', 300),
    ('N03', 'N01', 50), ('N01', 'N04', 100),
    ('N04', 'N05', 100), ('N05', 'N01', 100),
    ('N06', 'N07', 100), ('N06', 'N07', 110),
    ('N07', 'N08', 100), ('N08', 'N09', 100),
    ('N09', 'N06', 100), ('N06', 'N08', 100),
    ('N10', 'N11', 100), ('N11', 'N12', 100),
    ('N12', 'N10', 100), ('N01', 'N06', 100),
    ('N06', 'N10', 100),
]

conn = sqlite3.connect(path)
try:
    tables = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    ).fetchall()
    assert tables == [('edges',), ('nodes',)], tables
    assert conn.execute('PRAGMA table_info(nodes)').fetchall() == [
        (0, 'id', 'TEXT', 0, None, 1),
        (1, 'department', 'TEXT', 0, None, 0),
    ]
    assert conn.execute('PRAGMA table_info(edges)').fetchall() == [
        (0, 'src', 'TEXT', 0, None, 0),
        (1, 'dst', 'TEXT', 0, None, 0),
        (2, 'timestamp', 'INTEGER', 0, None, 0),
    ]
    assert conn.execute('SELECT id, department FROM nodes ORDER BY rowid').fetchall() == expected_nodes
    assert conn.execute('SELECT src, dst, timestamp FROM edges ORDER BY rowid').fetchall() == expected_edges
finally:
    conn.close()
PY

    local backup before_hash after_hash
    backup="$(mktemp /tmp/network.db.XXXXXX)" || return 1
    cp -p /home/user/network.db "$backup" || return 1
    chmod 600 "$backup"
    before_hash="$(sha256sum /home/user/network.db | awk '{print $1}')" || return 1

    restore_db() {
        cp -p "$backup" /home/user/network.db 2>/dev/null || true
        rm -f "$backup"
    }
    trap restore_db RETURN

    # The result must be produced by executing the requested Go source.
    rm -f /home/user/top_nodes.csv
    timeout 180s runuser -u user -- env HOME=/home/user GOPATH=/home/user/go \
        go run /home/user/analyze.go || return 1

    after_hash="$(sha256sum /home/user/network.db | awk '{print $1}')" || return 1
    test "$before_hash" = "$after_hash" || return 1

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import os
import secrets
import sqlite3
import subprocess
import pytest

DB_PATH = '/home/user/network.db'
OUTPUT_CSV_PATH = '/home/user/top_nodes.csv'


def get_expected_results(db_path):
    """Recomputes the expected results from the SQLite database."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    query = """
    WITH DedupedEdges AS (
        SELECT src, dst
        FROM edges
        GROUP BY src, dst
        HAVING timestamp = MAX(timestamp)
    ),
    NodeDegrees AS (
        SELECT n.id AS node_id, n.department,
               (SELECT COUNT(*) FROM DedupedEdges e WHERE e.src = n.id) +
               (SELECT COUNT(*) FROM DedupedEdges e WHERE e.dst = n.id) AS total_degree
        FROM nodes n
    ),
    RankedNodes AS (
        SELECT department, node_id, total_degree,
               DENSE_RANK() OVER (PARTITION BY department ORDER BY total_degree DESC) AS rank
        FROM NodeDegrees
    )
    SELECT department, node_id, total_degree, rank
    FROM RankedNodes
    WHERE rank <= 3
    ORDER BY department ASC, rank ASC, node_id ASC;
    """
    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()
    return [dict(row) for row in rows]


def read_csv(path):
    with open(path, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail('CSV file is empty.')

        expected_header = ['department', 'node_id', 'total_degree', 'rank']
        assert header == expected_header, (
            f'CSV header is incorrect. Expected {expected_header}, got {header}.'
        )

        data = []
        for row_num, row in enumerate(reader, start=2):
            assert len(row) == 4, (
                f'Row {row_num} does not have exactly 4 columns: {row}'
            )
            data.append({
                'department': row[0],
                'node_id': row[1],
                'total_degree': int(row[2]),
                'rank': int(row[3]),
            })
        return data


def test_csv_exists():
    """Test if the output CSV file exists."""
    assert os.path.isfile(OUTPUT_CSV_PATH), (
        f'Output CSV file {OUTPUT_CSV_PATH} is missing.'
    )


def test_csv_content_and_format():
    """Test exact content and format against the original database."""
    assert os.path.isfile(OUTPUT_CSV_PATH), 'Cannot test content: CSV file is missing.'
    expected_data = get_expected_results(DB_PATH)
    student_data = read_csv(OUTPUT_CSV_PATH)

    assert len(student_data) == len(expected_data), (
        f'Expected {len(expected_data)} rows in CSV, but found {len(student_data)}.'
    )
    for i, (student_row, expected_row) in enumerate(zip(student_data, expected_data)):
        assert student_row == expected_row, (
            f'Row {i + 2} mismatch. Expected {expected_row}, got {student_row}.'
        )


def test_program_on_fresh_database():
    """Execute the Go program against an unpredictable database fixture."""
    departments = [f'D_{secrets.token_hex(4)}' for _ in range(3)]
    nodes = []
    for department in departments:
        for _ in range(6):
            nodes.append((f'Node_{secrets.token_hex(6)}', department))

    pairs = set()
    # Give every node at least one incoming and outgoing edge.
    for i, (node_id, _) in enumerate(nodes):
        pairs.add((node_id, nodes[(i + 1) % len(nodes)][0]))
    while len(pairs) < 45:
        src = nodes[secrets.randbelow(len(nodes))][0]
        dst = nodes[secrets.randbelow(len(nodes))][0]
        pairs.add((src, dst))

    if os.path.exists(DB_PATH):
        os.unlink(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('CREATE TABLE nodes (id TEXT PRIMARY KEY, department TEXT)')
        conn.execute('CREATE TABLE edges (src TEXT, dst TEXT, timestamp INTEGER)')
        conn.executemany('INSERT INTO nodes(id, department) VALUES (?, ?)', nodes)
        for src, dst in pairs:
            newest = 100000 + secrets.randbelow(1000000)
            # Multiple stale rows ensure counting raw rows gives a wrong degree.
            conn.execute('INSERT INTO edges VALUES (?, ?, ?)', (src, dst, newest - 20))
            conn.execute('INSERT INTO edges VALUES (?, ?, ?)', (src, dst, newest))
            if secrets.randbelow(2):
                conn.execute('INSERT INTO edges VALUES (?, ?, ?)', (src, dst, newest - 10))
        conn.commit()
    finally:
        conn.close()
    os.chmod(DB_PATH, 0o666)

    expected = get_expected_results(DB_PATH)
    before = hashlib.sha256(open(DB_PATH, 'rb').read()).hexdigest()
    if os.path.exists(OUTPUT_CSV_PATH):
        os.unlink(OUTPUT_CSV_PATH)

    subprocess.run(
        ['runuser', '-u', 'user', '--', 'env', 'HOME=/home/user',
         'GOPATH=/home/user/go', 'go', 'run', '/home/user/analyze.go'],
        cwd='/home/user', timeout=180, check=True,
    )

    after = hashlib.sha256(open(DB_PATH, 'rb').read()).hexdigest()
    assert after == before, 'The Go program modified network.db.'
    assert os.path.isfile(OUTPUT_CSV_PATH), 'Go program did not create top_nodes.csv.'
    actual = read_csv(OUTPUT_CSV_PATH)
    assert actual == expected
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
    return 0
}

if run_verifier; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
