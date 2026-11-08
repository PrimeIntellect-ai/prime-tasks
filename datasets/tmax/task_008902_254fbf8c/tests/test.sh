#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest


def get_expected_results():
    db_path = '/home/user/financial.db'
    json_path = '/home/user/entities.json'

    with open(json_path, 'r') as f:
        entities = json.load(f)

    high_risk_accounts = {e['account_id'] for e in entities if e.get('high_risk')}

    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    c.execute("SELECT tx_id, sender_id, receiver_id, amount, timestamp FROM transactions WHERE amount > 10000")
    initial_txs = c.fetchall()

    c.execute("SELECT tx_id, sender_id, receiver_id, amount, timestamp FROM transactions")
    all_txs = c.fetchall()

    c.execute("SELECT id, address_id FROM accounts")
    account_addresses = dict(c.fetchall())
    conn.close()

    results = []
    for itx in initial_txs:
        itx_id, a_id, b_id, i_amt, i_ts = itx
        for stx in all_txs:
            stx_id, s_sender, c_id, s_amt, s_ts = stx
            if s_sender == b_id and s_ts > i_ts:
                if len({a_id, b_id, c_id}) == 3:
                    addr_a = account_addresses.get(a_id)
                    addr_c = account_addresses.get(c_id)
                    if addr_a is not None and addr_a == addr_c:
                        if a_id in high_risk_accounts or b_id in high_risk_accounts or c_id in high_risk_accounts:
                            results.append({
                                "initial_tx_id": itx_id,
                                "subsequent_tx_id": stx_id,
                                "sender_a_id": a_id,
                                "intermediary_b_id": b_id,
                                "receiver_c_id": c_id,
                                "shared_address_id": addr_a
                            })

    results.sort(key=lambda x: x["initial_tx_id"])
    return results


def test_audit_results():
    results_path = '/home/user/audit_results.json'
    assert os.path.exists(results_path), f"Output file {results_path} is missing."
    assert os.path.isfile(results_path), f"Expected {results_path} to be a file."

    with open(results_path, 'r') as f:
        try:
            actual_results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} does not contain valid JSON.")

    expected_results = get_expected_results()

    assert isinstance(actual_results, list), "Expected the output to be a JSON array."
    assert len(actual_results) == len(expected_results), f"Expected {len(expected_results)} results, found {len(actual_results)}."

    for actual, expected in zip(actual_results, expected_results):
        assert actual == expected, f"Mismatch in output. Expected {expected}, got {actual}."


def test_indexes_sql():
    sql_path = '/home/user/indexes.sql'
    assert os.path.exists(sql_path), f"Indexes file {sql_path} is missing."
    assert os.path.isfile(sql_path), f"Expected {sql_path} to be a file."

    with open(sql_path, 'r') as f:
        content = f.read()

    create_index_statements = re.findall(
        r'CREATE\s+(?:UNIQUE\s+)?INDEX\s+.*?;', content,
        re.IGNORECASE | re.DOTALL
    )
    assert len(create_index_statements) >= 2, "Expected at least 2 CREATE INDEX statements in indexes.sql."

    valid_targets = [
        r'transactions\s*\(\s*amount\s*\)',
        r'transactions\s*\(\s*sender_id\s*\)',
        r'transactions\s*\(\s*receiver_id\s*\)',
        r'accounts\s*\(\s*address_id\s*\)'
    ]

    matched_targets = 0
    for stmt in create_index_statements:
        for target in valid_targets:
            if re.search(target, stmt, re.IGNORECASE):
                matched_targets += 1
                break

    assert matched_targets >= 2, "Indexes should target transactions(amount), transactions(sender_id), transactions(receiver_id), or accounts(address_id)."

    with tempfile.TemporaryDirectory() as td:
        db_copy = os.path.join(td, 'financial.db')
        shutil.copy2('/home/user/financial.db', db_copy)
        conn = sqlite3.connect(db_copy)
        try:
            try:
                conn.executescript(content)
                conn.commit()
            except sqlite3.Error as exc:
                pytest.fail(f"indexes.sql is not valid executable SQLite SQL: {exc}")

            expected = {
                ('transactions', ('amount',)),
                ('transactions', ('sender_id',)),
                ('transactions', ('receiver_id',)),
                ('accounts', ('address_id',)),
            }
            actual_targets = set()
            for table in ('transactions', 'accounts'):
                for row in conn.execute(f'PRAGMA index_list("{table}")'):
                    index_name = row[1]
                    escaped = index_name.replace('"', '""')
                    columns = tuple(r[2] for r in conn.execute(f'PRAGMA index_info("{escaped}")'))
                    actual_targets.add((table, columns))

            assert len(actual_targets & expected) >= 2, (
                "indexes.sql must actually create at least two valid indexes on "
                "transactions(amount), transactions(sender_id), transactions(receiver_id), or accounts(address_id)."
            )
        finally:
            conn.close()


def _remove_sqlite_sidecars(path):
    for suffix in ('-wal', '-shm', '-journal'):
        try:
            os.remove(path + suffix)
        except FileNotFoundError:
            pass


def _install_challenge_database(db_path, entities_path):
    token = secrets.randbelow(500000) + 200000
    account_ids = [token + x for x in (11, 29, 47, 83, 101, 137, 181)]
    a, b, c, d, e, f, g = account_ids
    address_ids = [token + x for x in (1001, 2003, 3007, 4001)]
    addr_x, addr_y, addr_z, addr_other = address_ids

    tx_base = secrets.randbelow(500000) + 700000
    tx_ids = [tx_base + x for x in (3, 17, 31, 49, 67, 89, 107, 131, 151, 173)]

    _remove_sqlite_sidecars(db_path)
    try:
        os.remove(db_path)
    except FileNotFoundError:
        pass

    conn = sqlite3.connect(db_path)
    ccur = conn.cursor()
    ccur.execute('CREATE TABLE addresses (id INTEGER PRIMARY KEY, address_text TEXT)')
    ccur.execute('CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT, address_id INTEGER)')
    ccur.execute('CREATE TABLE transactions (tx_id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, amount REAL, timestamp DATETIME)')
    ccur.executemany('INSERT INTO addresses VALUES (?, ?)', [
        (addr_x, 'challenge-x'), (addr_y, 'challenge-y'),
        (addr_z, 'challenge-z'), (addr_other, 'challenge-other')
    ])
    ccur.executemany('INSERT INTO accounts VALUES (?, ?, ?)', [
        (a, 'A', addr_x), (b, 'B', addr_z), (c, 'C', addr_x),
        (d, 'D', addr_y), (e, 'E', addr_other), (f, 'F', addr_y),
        (g, 'G', addr_x)
    ])

    transactions = [
        (tx_ids[4], b, c, 12.0, '2025-04-01 10:00:00'),
        (tx_ids[0], a, b, 14000.0, '2025-04-01 10:00:00'),
        (tx_ids[7], e, f, 25.0, '2025-04-01 13:00:00'),
        (tx_ids[2], b, c, 19.0, '2025-04-01 11:00:00'),
        (tx_ids[1], d, e, 23000.0, '2025-04-01 12:00:00'),
        (tx_ids[9], d, e, 10000.0, '2025-04-01 09:00:00'),
        (tx_ids[5], a, e, 17000.0, '2025-04-01 14:00:00'),
        (tx_ids[8], e, c, 4.0, '2025-04-01 15:00:00'),
        (tx_ids[3], g, g, 50000.0, '2025-04-01 08:00:00'),
        (tx_ids[6], e, d, 9.0, '2025-04-01 11:00:00')
    ]
    ccur.executemany('INSERT INTO transactions VALUES (?, ?, ?, ?, ?)', transactions)
    conn.commit()
    conn.close()

    entities = [
        {'account_id': a, 'high_risk': False, 'business_type': 'retail'},
        {'account_id': b, 'high_risk': True, 'business_type': 'shell'},
        {'account_id': c, 'high_risk': False, 'business_type': 'retail'},
        {'account_id': d, 'high_risk': False, 'business_type': 'consulting'},
        {'account_id': e, 'high_risk': False, 'business_type': 'retail'},
        {'account_id': f, 'high_risk': True, 'business_type': 'shell'},
        {'account_id': g, 'high_risk': False, 'business_type': 'retail'}
    ]
    with open(entities_path, 'w') as fobj:
        json.dump(entities, fobj)


def test_python_retrieval_script_exists_and_runs():
    candidates = sorted(
        str(path) for path in Path('/home/user').rglob('*.py')
        if path.is_file() and not path.is_symlink()
    )
    assert candidates, "A Python retrieval script under /home/user is required."

    db_path = '/home/user/financial.db'
    entities_path = '/home/user/entities.json'
    results_path = '/home/user/audit_results.json'

    original_db = Path(db_path).read_bytes()
    original_entities = Path(entities_path).read_bytes()
    had_results = os.path.isfile(results_path)
    original_results = Path(results_path).read_bytes() if had_results else None
    errors = []

    try:
        for candidate in candidates:
            _install_challenge_database(db_path, entities_path)
            try:
                os.remove(results_path)
            except FileNotFoundError:
                pass

            expected = get_expected_results()
            try:
                proc = subprocess.run(
                    [sys.executable, candidate],
                    cwd=os.path.dirname(candidate) or '/home/user',
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=20
                )
            except (OSError, subprocess.TimeoutExpired) as exc:
                errors.append(f"{candidate}: {exc}")
                continue

            if proc.returncode != 0:
                errors.append(f"{candidate}: exited {proc.returncode}: {proc.stderr[-500:]}")
                continue
            if not os.path.isfile(results_path):
                errors.append(f"{candidate}: did not create {results_path}")
                continue

            try:
                with open(results_path, 'r') as fobj:
                    actual = json.load(fobj)
            except (OSError, json.JSONDecodeError) as exc:
                errors.append(f"{candidate}: invalid result JSON: {exc}")
                continue

            if actual == expected:
                return
            errors.append(f"{candidate}: produced incorrect results for the challenge database")

        pytest.fail("No submitted Python script correctly recomputed the joined results. " + " | ".join(errors))
    finally:
        _remove_sqlite_sidecars(db_path)
        Path(db_path).write_bytes(original_db)
        Path(entities_path).write_bytes(original_entities)
        if had_results:
            Path(results_path).write_bytes(original_results)
        else:
            try:
                os.remove(results_path)
            except FileNotFoundError:
                pass

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
