#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import sqlite3
import subprocess
from datetime import datetime, timedelta
from decimal import Decimal

import pytest

SCRIPT_PATH = '/home/user/pipeline.py'
DB_PATH = '/home/user/analytics.db'
PLAN_PATH = '/home/user/query_plan.txt'
OUTPUT_PATH = '/home/user/top_users.csv'
USERS_PATH = '/home/user/users.csv'
TRANSACTIONS_PATH = '/home/user/transactions.csv'

QUERY = "SELECT u.name, SUM(t.amount) as total_spent FROM users u JOIN transactions t ON u.user_id = t.user_id WHERE u.status = 'ACTIVE' AND t.tx_date BETWEEN '2023-01-01' AND '2023-12-31' GROUP BY u.user_id ORDER BY total_spent DESC LIMIT 5;"


def generate_expected_data():
    random.seed(42)
    users = []
    for i in range(1, 1001):
        status = 'ACTIVE' if random.random() > 0.2 else 'INACTIVE'
        users.append((i, f'User_{i}', status))

    start_date = datetime(2022, 1, 1)
    transactions = []
    for i in range(1, 10001):
        user_id = random.randint(1, 1000)
        amount = round(random.uniform(10.0, 500.0), 2)
        days_offset = random.randint(0, 730)
        tx_date = (start_date + timedelta(days=days_offset)).strftime('%Y-%m-%d')
        transactions.append((i, user_id, amount, tx_date))
    return users, transactions


EXPECTED_USERS, EXPECTED_TRANSACTIONS = generate_expected_data()


@pytest.fixture(scope='session', autouse=True)
def pipeline_run():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    for path in (DB_PATH, PLAN_PATH, OUTPUT_PATH):
        if os.path.lexists(path):
            os.remove(path)
    result = subprocess.run(
        ['python3', SCRIPT_PATH], capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, f"pipeline.py failed with error:\n{result.stderr}"
    return result


def test_pipeline_script_exists_and_runs(pipeline_run):
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert pipeline_run.returncode == 0, f"pipeline.py failed with error:\n{pipeline_run.stderr}"


def test_provided_csv_files_are_unchanged():
    with open(USERS_PATH, newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        actual_users = [(int(r[0]), r[1], r[2]) for r in reader]
    assert header == ['user_id', 'name', 'status'], 'Unexpected users.csv header.'
    assert actual_users == EXPECTED_USERS, 'users.csv was altered or does not contain the provided data.'

    with open(TRANSACTIONS_PATH, newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        actual_transactions = [(int(r[0]), int(r[1]), float(r[2]), r[3]) for r in reader]
    assert header == ['tx_id', 'user_id', 'amount', 'tx_date'], 'Unexpected transactions.csv header.'
    assert actual_transactions == EXPECTED_TRANSACTIONS, 'transactions.csv was altered or does not contain the provided data.'


def test_analytics_db_exists_and_contains_loaded_data():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} was not created."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='users';")
    assert cursor.fetchone() is not None, "Table 'users' does not exist in analytics.db."
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='transactions';")
    assert cursor.fetchone() is not None, "Table 'transactions' does not exist in analytics.db."

    cursor.execute('SELECT user_id, name, status FROM users ORDER BY user_id')
    assert cursor.fetchall() == EXPECTED_USERS, "The users table was not loaded from the provided CSV data."

    cursor.execute('SELECT tx_id, user_id, amount, tx_date FROM transactions ORDER BY tx_id')
    assert cursor.fetchall() == EXPECTED_TRANSACTIONS, "The transactions table was not loaded from the provided CSV data."
    conn.close()


def test_query_plan_output_and_real_indexes():
    assert os.path.isfile(PLAN_PATH), f"Query plan output {PLAN_PATH} was not created."

    with open(PLAN_PATH) as f:
        written_details = [line.strip() for line in f.read().splitlines() if line.strip()]

    content = '\n'.join(written_details).upper()
    assert 'USING INDEX' in content or 'USING COVERING INDEX' in content, \
        "The query plan does not indicate that an index was used. Please create appropriate indexes."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('EXPLAIN QUERY PLAN ' + QUERY)
    actual_details = [str(row[3]).strip() for row in cursor.fetchall()]

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND sql IS NOT NULL")
    user_indexes = [row[0] for row in cursor.fetchall()]
    conn.close()

    assert written_details == actual_details, \
        "query_plan.txt is not the raw detail output of EXPLAIN QUERY PLAN for the required query."
    assert user_indexes, "No real SQLite indexes were created."
    assert any(index_name.upper() in content for index_name in user_indexes), \
        "The required query plan does not use any index created by the pipeline."

    for detail in actual_details:
        words = detail.upper().split()
        if len(words) >= 2 and words[0] == 'SCAN':
            assert words[1] not in {'U', 'T', 'USERS', 'TRANSACTIONS'}, \
                f"The required query performs an avoidable full scan: {detail}"


def independently_derived_results():
    active = {user_id: name for user_id, name, status in EXPECTED_USERS if status == 'ACTIVE'}
    totals = {}
    for _tx_id, user_id, amount, tx_date in EXPECTED_TRANSACTIONS:
        if user_id in active and '2023-01-01' <= tx_date <= '2023-12-31':
            totals[user_id] = totals.get(user_id, Decimal('0')) + Decimal(str(amount))
    ranked = sorted(totals.items(), key=lambda item: item[1], reverse=True)[:5]
    return [(active[user_id], f'{total:.2f}') for user_id, total in ranked]


def test_top_users_output():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created."

    expected_results = [
        ('User_633', 3630.98),
        ('User_379', 3593.45),
        ('User_407', 3543.83),
        ('User_54', 3427.02),
        ('User_666', 3398.70)
    ]

    with open(OUTPUT_PATH, newline='') as f:
        rows = list(csv.reader(f))

    assert len(rows) > 0, f"File {OUTPUT_PATH} is empty."
    header = rows[0]
    assert header == ['name', 'total_spent'], f"Unexpected header in {OUTPUT_PATH}: {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 5, f"Expected exactly 5 rows in {OUTPUT_PATH}, found {len(data_rows)}."
    assert all(len(row) == 2 for row in data_rows), 'Each output row must contain exactly two columns.'

    for i, (expected_name, expected_spent) in enumerate(expected_results):
        actual_name = data_rows[i][0]
        actual_spent = float(data_rows[i][1])
        assert actual_name == expected_name, f"Row {i+1}: expected name {expected_name}, got {actual_name}."
        assert abs(actual_spent - expected_spent) < 0.01, f"Row {i+1}: expected total_spent {expected_spent}, got {actual_spent}."

    derived = independently_derived_results()
    assert [tuple(row) for row in data_rows] == derived, \
        "top_users.csv was not computed from the provided users and transactions data."

    conn = sqlite3.connect(DB_PATH)
    db_results = conn.execute(QUERY).fetchall()
    conn.close()
    formatted_db_results = [(name, f'{total:.2f}') for name, total in db_results]
    assert formatted_db_results == derived, \
        "Executing the required analytical query against analytics.db does not produce the required results."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
