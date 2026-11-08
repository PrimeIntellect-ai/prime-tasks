#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile

import pandas as pd
import pytest


def test_etl_cpp_exists():
    assert os.path.isfile('/home/user/etl.cpp'), "/home/user/etl.cpp is missing"


def test_etl_bin_exists():
    assert os.path.isfile('/home/user/etl_bin'), "/home/user/etl_bin is missing"
    assert os.access('/home/user/etl_bin', os.X_OK), "/home/user/etl_bin is not executable"


def test_summary_csv_exists():
    assert os.path.isfile('/home/user/summary.csv'), "/home/user/summary.csv is missing"


def test_summary_csv_metric():
    csv_path = '/home/user/summary.csv'
    assert os.path.isfile(csv_path), f"{csv_path} is missing"

    try:
        agent_df = pd.read_csv(csv_path)
    except Exception as e:
        pytest.fail(f"Failed to read {csv_path}: {e}")

    assert 'session_id' in agent_df.columns, "Column 'session_id' missing in summary.csv"
    assert 'total_amount' in agent_df.columns, "Column 'total_amount' missing in summary.csv"

    try:
        agent_df['total_amount'] = agent_df['total_amount'].astype(float).round(2)
    except Exception as e:
        pytest.fail(f"Failed to convert total_amount to float: {e}")

    expected = {101: 50.00, 102: 100.00, 103: 100.00}

    correct = 0
    for _, row in agent_df.iterrows():
        try:
            sid = int(row['session_id'])
            amt = float(row['total_amount'])
            if sid in expected and abs(expected[sid] - amt) < 0.01:
                correct += 1
        except ValueError:
            continue

    precision = correct / len(agent_df) if len(agent_df) > 0 else 0
    recall = correct / len(expected)
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0

    assert f1 >= 1.0, f"F1 Score is {f1:.2f}, expected >= 1.0"


def _run(executable):
    if os.path.exists('/home/user/summary.csv'):
        os.unlink('/home/user/summary.csv')
    result = subprocess.run(
        [executable], cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"{executable} failed with exit code {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile('/home/user/summary.csv'), (
        f"{executable} did not generate /home/user/summary.csv"
    )


def _check_dynamic_csv(expected):
    with open('/home/user/summary.csv', newline='') as f:
        rows = list(csv.reader(f))

    assert rows, "summary.csv is empty"
    assert rows[0] == ['session_id', 'total_amount'], (
        "summary.csv must have exactly the header session_id,total_amount"
    )
    assert len(rows) == len(expected) + 1, "summary.csv has missing or extra rows"

    actual = {}
    for row in rows[1:]:
        assert len(row) == 2, f"Malformed CSV row: {row}"
        assert re.fullmatch(r'-?\d+\.\d{2}', row[1]), (
            f"total_amount is not formatted to two decimal places: {row[1]}"
        )
        sid = int(row[0])
        assert sid not in actual, f"Duplicate session_id {sid}"
        actual[sid] = int(round(float(row[1]) * 100))

    assert actual == expected, f"Incorrect temporal aggregation: {actual} != {expected}"


def test_program_compiles_uses_sqlite_and_handles_unseen_data():
    source = open('/home/user/etl.cpp', encoding='utf-8', errors='replace').read()
    lower = source.lower()
    assert re.search(r'#\s*include\s*[<\"]sqlite3\.h[>\"]', source), (
        "etl.cpp must include sqlite3.h"
    )
    for term in ('orders', 'sessions', 'user_id', 'order_time', 'start_time', 'end_time'):
        assert term in lower, f"etl.cpp does not reference required relationship field {term}"

    rebuilt = '/tmp/etl_rebuilt'
    compile_result = subprocess.run(
        ['g++', '-std=c++17', '/home/user/etl.cpp', '-o', rebuilt, '-lsqlite3'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, f"etl.cpp does not compile: {compile_result.stderr}"

    with open('/home/user/etl_bin', 'rb') as f:
        assert f.read(4) == b'\x7fELF', "/home/user/etl_bin is not a compiled executable"

    symbols = subprocess.check_output(['nm', '-D', rebuilt], text=True, errors='replace')
    assert re.search(r'\bsqlite3_open(?:_v2)?(?:@|\b)', symbols), (
        "compiled source does not use sqlite3_open/sqlite3_open_v2"
    )
    query_api = (
        re.search(r'\bsqlite3_exec(?:@|\b)', symbols)
        or re.search(r'\bsqlite3_get_table(?:@|\b)', symbols)
        or (
            re.search(r'\bsqlite3_prepare(?:_v2)?(?:@|\b)', symbols)
            and re.search(r'\bsqlite3_step(?:@|\b)', symbols)
        )
    )
    assert query_api, "compiled source does not query through the SQLite C API"

    rng = random.SystemRandom()
    base = rng.randrange(20000, 80000)
    session_ids = [rng.randrange(200000, 900000) for _ in range(5)]
    while len(set(session_ids)) != 5:
        session_ids = [rng.randrange(200000, 900000) for _ in range(5)]

    sessions = [
        (session_ids[0], 11, base, base + 99),
        (session_ids[1], 11, base + 200, base + 349),
        (session_ids[2], 11, base + 500, base + 699),
        (session_ids[3], 22, base + 50, base + 250),
        (session_ids[4], 33, base + 800, base + 999),
    ]

    expected = {sid: 0 for sid in session_ids}
    orders = []
    order_id = 1
    for sid, uid, start, end in sessions:
        # Boundary and interior orders ensure both temporal predicates matter.
        for when in (start, (start + end) // 2, end):
            cents = rng.randrange(101, 20000)
            orders.append((order_id, uid, when, cents / 100.0))
            expected[sid] += cents
            order_id += 1

    # Same-user orders outside every applicable window expose a user_id-only join.
    for uid, when in ((11, base - 20), (11, base + 750), (22, base + 400), (33, base + 1100)):
        orders.append((order_id, uid, when, rng.randrange(5000, 30000) / 100.0))
        order_id += 1

    db_backup = tempfile.mktemp(prefix='data.db.backup.')
    summary_backup = tempfile.mktemp(prefix='summary.csv.backup.')
    had_summary = os.path.isfile('/home/user/summary.csv')
    shutil.copy2('/app/data.db', db_backup)
    if had_summary:
        shutil.copy2('/home/user/summary.csv', summary_backup)

    try:
        os.unlink('/app/data.db')
        conn = sqlite3.connect('/app/data.db')
        conn.executescript('''
            CREATE TABLE users (user_id INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE sessions (
                session_id INTEGER PRIMARY KEY, user_id INTEGER,
                start_time INTEGER, end_time INTEGER
            );
            CREATE TABLE orders (
                order_id INTEGER PRIMARY KEY, user_id INTEGER,
                order_time INTEGER, amount REAL
            );
        ''')
        conn.executemany('INSERT INTO users VALUES (?, ?)', [(11, 'U11'), (22, 'U22'), (33, 'U33')])
        conn.executemany('INSERT INTO sessions VALUES (?, ?, ?, ?)', sessions)
        conn.executemany('INSERT INTO orders VALUES (?, ?, ?, ?)', orders)
        conn.commit()
        conn.close()
        os.chmod('/app/data.db', 0o666)

        # Exercise both the artifact supplied by the agent and a fresh build of its source.
        _run('/home/user/etl_bin')
        _check_dynamic_csv(expected)
        _run(rebuilt)
        _check_dynamic_csv(expected)
    finally:
        shutil.copy2(db_backup, '/app/data.db')
        os.unlink(db_backup)
        if had_summary:
            shutil.copy2(summary_backup, '/home/user/summary.csv')
            os.unlink(summary_backup)
        elif os.path.exists('/home/user/summary.csv'):
            os.unlink('/home/user/summary.csv')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
