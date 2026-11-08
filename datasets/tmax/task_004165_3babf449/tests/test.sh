#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import shutil
import sqlite3
import tempfile
from collections import deque

DB_PATH = '/home/user/network.db'
SQL_PATH = '/home/user/aggregate.sql'
CSV_PATH = '/home/user/top_users.csv'
PATH_FILE = '/home/user/shortest_path.txt'


def expected_rows(db_path):
    conn = sqlite3.connect(db_path)
    users = conn.execute('SELECT user_id, region FROM users').fetchall()
    counts = dict(conn.execute('''
        SELECT u.user_id, COUNT(m.msg_id)
        FROM users AS u
        LEFT JOIN messages AS m ON m.sender_id = u.user_id
        GROUP BY u.user_id
    ''').fetchall())
    conn.close()

    by_region = {}
    for user_id, region in users:
        by_region.setdefault(region, []).append(counts[user_id])

    ranks = {
        region: {count: i + 1 for i, count in enumerate(sorted(set(values), reverse=True))}
        for region, values in by_region.items()
    }
    return sorted(
        (int(user_id), str(region), int(counts[user_id]), int(ranks[region][counts[user_id]]))
        for user_id, region in users
    )


def execute_submission(db_path):
    with open(SQL_PATH, 'r') as f:
        sql = f.read()

    conn = sqlite3.connect(f'file:{db_path}?mode=ro', uri=True)
    allowed = {sqlite3.SQLITE_SELECT, sqlite3.SQLITE_READ, sqlite3.SQLITE_FUNCTION}
    if hasattr(sqlite3, 'SQLITE_RECURSIVE'):
        allowed.add(sqlite3.SQLITE_RECURSIVE)
    conn.set_authorizer(lambda action, arg1, arg2, db, source:
                        sqlite3.SQLITE_OK if action in allowed else sqlite3.SQLITE_DENY)
    conn.set_progress_handler(lambda: 1, 2_000_000)
    try:
        cursor = conn.execute(sql)
        assert cursor.description is not None, 'aggregate.sql must execute a query returning rows'
        headers = [column[0] for column in cursor.description]
        raw_rows = cursor.fetchall()
    finally:
        conn.close()

    assert len(headers) == 4, f'aggregate.sql must return four columns, got {headers}'
    rows = []
    for row in raw_rows:
        assert len(row) == 4, f'Expected four values per SQL row, got {row}'
        assert None not in row, f'Unexpected NULL in SQL result: {row}'
        rows.append((int(row[0]), str(row[1]), int(row[2]), int(row[3])))
    return headers, sorted(rows)


def validate_header(header):
    normalized = [value.strip().lower() for value in header]
    assert normalized[0] == 'user_id', f'First header must be user_id, got {header}'
    assert normalized[1] == 'region', f'Second header must be region, got {header}'
    assert normalized[2] in {'msg_count', 'message_count'}, \
        f'Third header must identify the message count, got {header}'
    assert normalized[3] in {'rank', 'dense_rank'}, \
        f'Fourth header must identify the rank, got {header}'


def test_aggregate_sql_fixed_and_executable():
    assert os.path.isfile(SQL_PATH), f'SQL script missing at {SQL_PATH}'
    with open(SQL_PATH, 'r') as f:
        content = f.read().upper()

    # Preserve the original cross-join and JOIN/WHERE assertions.
    assert 'FROM USERS U, MESSAGES M' not in content, \
        'The aggregate.sql still contains the buggy implicit cross join.'
    assert 'JOIN' in content or 'WHERE' in content, \
        'The query does not seem to use an explicit JOIN or WHERE clause to fix the cross join.'

    headers, actual = execute_submission(DB_PATH)
    validate_header(headers)
    assert actual == expected_rows(DB_PATH), \
        f'aggregate.sql returned incorrect rows. Expected {expected_rows(DB_PATH)}, got {actual}'

    # Exercise the submitted SQL against an unpredictable modified copy so a fixed answer cannot pass.
    with tempfile.TemporaryDirectory() as tempdir:
        mutated = os.path.join(tempdir, 'network.db')
        shutil.copy2(DB_PATH, mutated)
        conn = sqlite3.connect(mutated)
        max_user = conn.execute('SELECT COALESCE(MAX(user_id), 0) FROM users').fetchone()[0]
        max_msg = conn.execute('SELECT COALESCE(MAX(msg_id), 0) FROM messages').fetchone()[0]
        existing_ids = [row[0] for row in conn.execute('SELECT user_id FROM users').fetchall()]
        region = 'VerifierRegion_' + secrets.token_hex(6)
        new_users = [max_user + 1, max_user + 2, max_user + 3]
        conn.executemany('INSERT INTO users(user_id, name, region) VALUES (?, ?, ?)', [
            (new_users[0], 'Verifier A', region),
            (new_users[1], 'Verifier B', region),
            (new_users[2], 'Verifier C', region),
        ])
        next_msg = max_msg + 1
        receiver = existing_ids[0]
        tied_count = 3 + secrets.randbelow(5)
        for sender, count in ((new_users[0], tied_count), (new_users[1], tied_count), (new_users[2], 0)):
            for _ in range(count):
                conn.execute('INSERT INTO messages(msg_id, sender_id, receiver_id) VALUES (?, ?, ?)',
                             (next_msg, sender, receiver))
                next_msg += 1
        for sender in existing_ids:
            for _ in range(secrets.randbelow(4)):
                conn.execute('INSERT INTO messages(msg_id, sender_id, receiver_id) VALUES (?, ?, ?)',
                             (next_msg, sender, receiver))
                next_msg += 1
        conn.commit()
        conn.close()

        _, mutated_actual = execute_submission(mutated)
        mutated_expected = expected_rows(mutated)
        assert mutated_actual == mutated_expected, \
            f'aggregate.sql failed on modified data. Expected {mutated_expected}, got {mutated_actual}'


def test_top_users_csv():
    assert os.path.isfile(CSV_PATH), f'CSV file missing at {CSV_PATH}'
    with open(CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, 'CSV file is empty or missing header'
        rows = list(reader)

    assert len(rows) > 0, 'CSV file contains no data rows'
    validate_header(header)
    assert all(len(row) == 4 for row in rows), 'Every CSV data row must have four columns'

    parsed = sorted((int(r[0].strip()), r[1].strip(), int(r[2].strip()), int(r[3].strip())) for r in rows)
    expected = expected_rows(DB_PATH)
    assert parsed == expected, f'CSV must contain every user with correct count, region, and rank: {expected}'

    # Preserve the original specific count assertions.
    by_id = {row[0]: row for row in parsed}
    assert 1 in by_id, 'User 1 not found in top_users.csv'
    assert by_id[1][2] == 5, f'User 1 should have 5 messages, found {by_id[1][2]}'
    assert 3 in by_id, 'User 3 not found in top_users.csv'
    assert by_id[3][2] == 4, f'User 3 should have 4 messages, found {by_id[3][2]}'

    sql_headers, sql_rows = execute_submission(DB_PATH)
    assert [x.strip().lower() for x in header] == [x.strip().lower() for x in sql_headers], \
        'CSV header must be the header produced by aggregate.sql'
    assert parsed == sql_rows, 'top_users.csv must contain the results produced by aggregate.sql'


def test_shortest_path_txt():
    assert os.path.isfile(PATH_FILE), f'Shortest path file missing at {PATH_FILE}'
    with open(PATH_FILE, 'r') as f:
        content = f.read().strip()

    # Preserve the original assertion for the supplied database.
    assert content == '1,5,6,3', \
        f"Shortest path incorrect. Expected '1,5,6,3', got '{content}'"

    rows = expected_rows(DB_PATH)
    north = [r[0] for r in rows if r[1] == 'North' and r[3] == 1]
    south = [r[0] for r in rows if r[1] == 'South' and r[3] == 1]
    assert len(north) == 1 and len(south) == 1, 'Expected unique #1 users in North and South'
    start, goal = north[0], south[0]

    conn = sqlite3.connect(DB_PATH)
    edges = conn.execute('SELECT user1_id, user2_id FROM connections').fetchall()
    conn.close()
    graph = {}
    for a, b in edges:
        graph.setdefault(a, set()).add(b)
        graph.setdefault(b, set()).add(a)

    submitted = [int(part) for part in content.split(',')]
    assert submitted[0] == start and submitted[-1] == goal, \
        'Path must start at the North #1 user and end at the South #1 user'
    assert all(b in graph.get(a, set()) for a, b in zip(submitted, submitted[1:])), \
        'shortest_path.txt contains a pair that is not connected'

    queue = deque([(start, 0)])
    visited = {start}
    shortest = None
    while queue:
        node, distance = queue.popleft()
        if node == goal:
            shortest = distance
            break
        for neighbor in graph.get(node, set()):
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append((neighbor, distance + 1))
    assert shortest is not None, 'No graph path exists between the selected users'
    assert len(submitted) - 1 == shortest, 'The submitted graph path is not a shortest path'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
