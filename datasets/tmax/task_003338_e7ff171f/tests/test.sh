#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import stat
import subprocess
from collections import defaultdict, deque

import pytest

DB_PATH = "/home/user/financial_audit.db"
RESULT_PATH = "/home/user/audit_result.json"
SOURCE_PATH = "/home/user/audit.go"
BINARY_PATH = "/tmp/audit_submission"

CANONICAL_ACCOUNTS = [
    (1, 'ShellCorp'),
    (2, 'MixerA'),
    (3, 'MixerB'),
    (4, 'LegitCorp'),
    (5, 'OffshoreVault'),
    (6, 'BribeAccount'),
]

CANONICAL_TRANSFERS = [
    (1, 1, 2, 100, 1),
    (2, 1, 3, 100, 2),
    (3, 1, 2, 500, 3),
    (4, 1, 6, 50, 4),
    (5, 2, 4, 1000, 1),
    (6, 2, 5, 2000, 2),
    (7, 2, 6, 2500, 3),
    (8, 2, 3, 3000, 4),
    (9, 3, 4, 100, 1),
    (10, 3, 5, 500, 2),
    (11, 4, 5, 10000, 1),
]

CHALLENGE_ACCOUNTS = [
    (1, 'ShellCorp'),
    (2, 'Alpha'),
    (3, 'HubZ'),
    (4, 'OffshoreVault'),
    (5, 'X'),
    (6, 'Y'),
    (7, 'Z'),
]

CHALLENGE_TRANSFERS = [
    # The fourth ShellCorp transfer is flagged only when the frame is the
    # current row and two preceding rows, rather than the full history.
    (101, 1, 5, 1000, 10),
    (102, 1, 6, 1000, 20),
    (103, 1, 7, 1, 30),
    (104, 1, 2, 600, 40),
    (105, 2, 5, 5, 10),
    (106, 2, 4, 15, 20),
    (107, 3, 5, 10, 10),
    (108, 3, 5, 20, 20),
    (109, 3, 6, 40, 30),
    (110, 3, 7, 80, 40),
]


def strip_go_comments(source):
    out = []
    i = 0
    state = 'code'
    while i < len(source):
        ch = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ''
        if state == 'code':
            if ch == '/' and nxt == '/':
                state = 'line_comment'
                i += 2
                continue
            if ch == '/' and nxt == '*':
                state = 'block_comment'
                i += 2
                continue
            out.append(ch)
            if ch == '"':
                state = 'quoted'
            elif ch == '`':
                state = 'raw'
            elif ch == "'":
                state = 'rune'
            i += 1
        elif state == 'line_comment':
            if ch == '\n':
                out.append(ch)
                state = 'code'
            i += 1
        elif state == 'block_comment':
            if ch == '*' and nxt == '/':
                state = 'code'
                i += 2
            else:
                if ch == '\n':
                    out.append(ch)
                i += 1
        elif state == 'raw':
            out.append(ch)
            i += 1
            if ch == '`':
                state = 'code'
        else:
            out.append(ch)
            if ch == '\\' and i + 1 < len(source):
                out.append(source[i + 1])
                i += 2
            else:
                i += 1
                if (state == 'quoted' and ch == '"') or (state == 'rune' and ch == "'"):
                    state = 'code'
    return ''.join(out)


def extract_go_strings(source):
    strings = []
    for match in re.finditer(r'`([^`]*)`|"(?:\\.|[^"\\])*"', source, re.S):
        token = match.group(0)
        if token.startswith('`'):
            strings.append(token[1:-1])
        else:
            try:
                strings.append(json.loads(token))
            except json.JSONDecodeError:
                pass
    return ' '.join(strings)


def create_db(accounts, transfers):
    for path in (DB_PATH, DB_PATH + '-wal', DB_PATH + '-shm', DB_PATH + '-journal'):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT)')
        conn.execute('CREATE TABLE transfers (tx_id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, amount REAL, timestamp INTEGER)')
        conn.executemany('INSERT INTO accounts VALUES (?, ?)', accounts)
        conn.executemany('INSERT INTO transfers VALUES (?, ?, ?, ?, ?)', transfers)
        conn.commit()
    finally:
        conn.close()


def database_snapshot():
    conn = sqlite3.connect(DB_PATH)
    try:
        accounts = conn.execute('SELECT id, name FROM accounts ORDER BY id').fetchall()
        transfers = conn.execute(
            'SELECT tx_id, sender_id, receiver_id, amount, timestamp FROM transfers ORDER BY tx_id'
        ).fetchall()
        return accounts, transfers
    finally:
        conn.close()


def compute_truth():
    if not os.path.exists(DB_PATH):
        pytest.fail(f'Database missing at {DB_PATH}')

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        c = conn.cursor()
        c.execute('SELECT id, name FROM accounts')
        accounts = {row['id']: row['name'] for row in c.fetchall()}
        c.execute('SELECT tx_id, sender_id, receiver_id, amount, timestamp FROM transfers ORDER BY sender_id, timestamp')
        transfers = c.fetchall()
    finally:
        conn.close()

    flagged_edges = []
    history = defaultdict(list)
    for tx in transfers:
        sender = tx['sender_id']
        history[sender].append(tx['amount'])
        recent = history[sender][-3:]
        avg = sum(recent) / len(recent)
        if tx['amount'] > avg:
            flagged_edges.append((accounts[sender], accounts[tx['receiver_id']]))

    graph = defaultdict(list)
    out_degree = defaultdict(int)
    for u, v in flagged_edges:
        graph[u].append(v)
        out_degree[u] += 1
        if v not in out_degree:
            out_degree[v] = 0

    queue = deque([['ShellCorp']])
    visited = {'ShellCorp'}
    shortest_path = None
    while queue:
        path = queue.popleft()
        node = path[-1]
        if node == 'OffshoreVault':
            shortest_path = path
            break
        for neighbor in graph[node]:
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append(path + [neighbor])

    highest_out_degree = None
    if out_degree:
        max_degree = max(out_degree.values())
        highest_out_degree = sorted(
            node for node, degree in out_degree.items() if degree == max_degree
        )[0]

    return {
        'shortest_path': shortest_path,
        'highest_out_degree': highest_out_degree,
    }


def run_and_check(accounts, transfers):
    create_db(accounts, transfers)
    truth = compute_truth()
    before = database_snapshot()

    try:
        os.remove(RESULT_PATH)
    except FileNotFoundError:
        pass

    completed = subprocess.run(
        [BINARY_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f'audit.go execution failed with exit code {completed.returncode}: '
        f'{completed.stderr[-2000:]}'
    )

    assert database_snapshot() == before, 'The audit program modified the supplied database'
    assert os.path.exists(RESULT_PATH), f'Result file missing at {RESULT_PATH}'
    assert os.path.isfile(RESULT_PATH), f'{RESULT_PATH} is not a file'

    try:
        with open(RESULT_PATH, 'r') as f:
            result = json.load(f)
    except json.JSONDecodeError:
        pytest.fail('Result file is not valid JSON')

    assert 'shortest_path' in result, "Missing 'shortest_path' in result JSON"
    assert 'highest_out_degree' in result, "Missing 'highest_out_degree' in result JSON"
    assert result['shortest_path'] == truth['shortest_path'], (
        f"Expected shortest_path {truth['shortest_path']}, got {result['shortest_path']}"
    )
    assert result['highest_out_degree'] == truth['highest_out_degree'], (
        f"Expected highest_out_degree {truth['highest_out_degree']}, got {result['highest_out_degree']}"
    )


def test_audit_program_exists_and_contains_window_query():
    assert os.path.exists(SOURCE_PATH), f'Go program missing at {SOURCE_PATH}'
    mode = os.lstat(SOURCE_PATH).st_mode
    assert stat.S_ISREG(mode), f'{SOURCE_PATH} must be a regular file'

    with open(SOURCE_PATH, 'r', encoding='utf-8') as f:
        source = strip_go_comments(f.read())
    sql_text = extract_go_strings(source)

    assert re.search(r'\bavg\s*\([^)]*\)\s*over\s*\(', sql_text, re.I | re.S), \
        'audit.go must use AVG as a SQL window function'
    assert re.search(r'partition\s+by.{0,100}\bsender_id\b', sql_text, re.I | re.S), \
        'The SQL window must partition by sender_id'
    assert re.search(r'order\s+by.{0,100}\btimestamp\b', sql_text, re.I | re.S), \
        'The SQL window must order by timestamp'
    assert re.search(
        r'rows\s+(?:between\s+2\s+preceding\s+and\s+current\s+row|2\s+preceding)',
        sql_text,
        re.I | re.S,
    ), 'The SQL window must include the current row and up to two preceding rows'
    assert re.search(r'\.\s*(?:query|querycontext)\s*\(', source, re.I), \
        'audit.go must execute a database query'


def test_program_executes_and_computes_results():
    build = subprocess.run(
        ['go', 'build', '-o', BINARY_PATH, SOURCE_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert build.returncode == 0, f'audit.go does not build: {build.stderr[-3000:]}'
    assert os.path.isfile(BINARY_PATH), 'Go build did not produce an executable'

    # Preserve the original checks against the canonical database, then use a
    # second unseen database to ensure the program performs the requested work.
    run_and_check(CANONICAL_ACCOUNTS, CANONICAL_TRANSFERS)
    run_and_check(CHALLENGE_ACCOUNTS, CHALLENGE_TRANSFERS)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
