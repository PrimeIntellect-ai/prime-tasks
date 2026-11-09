#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import secrets
import sqlite3
import subprocess

CPP = "/home/user/analyzer.cpp"
EXE = "/home/user/analyzer"
DB = "/home/user/ecommerce.db"
REPORT = "/home/user/report.csv"
PLAN = "/home/user/query_plan.txt"

# Preserve the original source and executable assertions.
assert os.path.isfile(CPP), f"Source file {CPP} does not exist."
with open(CPP, "r", encoding="utf-8") as f:
    source = f.read()
assert "sqlite3_" in source, "The C++ program does not appear to use the sqlite3 API."
assert "<sqlite3.h>" in source, "The C++ program does not include <sqlite3.h>."
assert os.path.isfile(EXE), f"Executable {EXE} does not exist. Did it compile successfully?"
assert os.access(EXE, os.X_OK), f"File {EXE} is not executable."

# Replace the agent-writable database with a fresh, unpredictable challenge DB.
# Expected results and original table contents are retained in this verifier's
# memory, so changing/deleting database rows cannot change the expected answer.
for path in (DB, DB + "-wal", DB + "-shm", DB + "-journal", REPORT, PLAN):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

rng = random.Random(secrets.randbits(128))
suffix = secrets.token_hex(8)
old_indexes = {"idx_bad", f"old_tx_user_{suffix}", f"old_tx_date_product_{suffix}"}

conn = sqlite3.connect(DB)
cur = conn.cursor()
cur.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, region TEXT)")
cur.execute("CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, category TEXT)")
cur.execute("CREATE TABLE transactions (id INTEGER PRIMARY KEY, user_id INTEGER, product_id INTEGER, amount REAL, tx_date TEXT)")

users = [(i, f"ChallengeUser_{i:03d}_{suffix[:4]}", rng.choice(["North", "South", "East", "West"])) for i in range(1, 61)]
products = []
for i in range(1, 25):
    category = "Electronics" if i <= 8 else rng.choice(["Clothing", "Home", "Toys"])
    products.append((i, f"ChallengeProduct_{i:03d}", category))
cur.executemany("INSERT INTO users VALUES (?, ?, ?)", users)
cur.executemany("INSERT INTO products VALUES (?, ?, ?)", products)

transactions = []
for i in range(1, 12001):
    month = rng.randint(1, 12)
    day = rng.randint(1, 28)
    transactions.append((
        i,
        rng.randint(1, 60),
        rng.randint(1, 24),
        round(rng.uniform(1.0, 1500.0), 2),
        f"2023-{month:02d}-{day:02d}",
    ))
cur.executemany("INSERT INTO transactions VALUES (?, ?, ?, ?, ?)", transactions)
cur.execute("CREATE INDEX idx_bad ON transactions(amount)")
cur.execute(f'CREATE INDEX "old_tx_user_{suffix}" ON transactions(user_id)')
cur.execute(f'CREATE INDEX "old_tx_date_product_{suffix}" ON transactions(tx_date, product_id)')
conn.commit()

query = """
SELECT u.name, SUM(t.amount) AS total_volume, AVG(t.amount) AS avg_amount
FROM users u
JOIN transactions t ON u.id = t.user_id
JOIN products p ON t.product_id = p.id
WHERE p.category = 'Electronics'
  AND t.tx_date BETWEEN '2023-10-01' AND '2023-12-31'
GROUP BY u.id
ORDER BY total_volume DESC, u.name ASC
LIMIT 5;
"""
expected_rows = cur.execute(query).fetchall()
assert len(expected_rows) == 5, "Internal challenge database did not produce five rows."
original_users = cur.execute("SELECT * FROM users ORDER BY id").fetchall()
original_products = cur.execute("SELECT * FROM products ORDER BY id").fetchall()
original_transactions = cur.execute("SELECT * FROM transactions ORDER BY id").fetchall()
conn.close()

# Rebuild from the submitted source using the exact required compilation options,
# then execute the resulting artifact against the fresh challenge database.
build = subprocess.run(
    ["g++", "-O3", "-std=c++17", CPP, "-lsqlite3", "-o", EXE],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    timeout=60,
)
assert build.returncode == 0, "Submitted analyzer.cpp did not compile:\n" + build.stdout
assert os.path.isfile(EXE) and os.access(EXE, os.X_OK), "Compiled analyzer is not executable."
run = subprocess.run(
    [EXE],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    timeout=60,
)
assert run.returncode == 0, "Submitted analyzer failed when executed:\n" + run.stdout

# The analyzer is supposed to modify indexes only, not the source data.
assert os.path.isfile(DB), f"Database file {DB} does not exist."
conn = sqlite3.connect(DB)
cur = conn.cursor()
assert cur.execute("SELECT * FROM users ORDER BY id").fetchall() == original_users, "The users table was modified."
assert cur.execute("SELECT * FROM products ORDER BY id").fetchall() == original_products, "The products table was modified."
assert cur.execute("SELECT * FROM transactions ORDER BY id").fetchall() == original_transactions, "The transactions table was modified."

# Preserve the original index assertions and additionally ensure every hidden
# pre-existing transaction index was dropped.
index_rows = cur.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='transactions'").fetchall()
indexes = {row[0] for row in index_rows}
assert "idx_bad" not in indexes, "The corrupted index 'idx_bad' was not dropped."
assert len(indexes) > 0, "No new indexes were created on the transactions table."
for old_name in old_indexes:
    assert old_name not in indexes, f"Pre-existing transaction index {old_name!r} was not dropped."

# At least one new transaction index must cover every transaction column used by
# the analytical query and begin with a constrained join/filter column.
required_columns = {"product_id", "tx_date", "user_id", "amount"}
covering_indexes = set()
for name in indexes:
    quoted = name.replace('"', '""')
    info = cur.execute(f'PRAGMA index_info("{quoted}")').fetchall()
    columns = [row[2] for row in info]
    if columns and columns[0] in {"product_id", "tx_date"} and required_columns.issubset(set(columns)):
        covering_indexes.add(name)
assert covering_indexes, "No beneficial covering index for the analytical query was created."

# Independently derive the real query plan and require SQLite to use one of the
# submitted covering indexes.
actual_plan_details = [row[3] for row in cur.execute("EXPLAIN QUERY PLAN " + query).fetchall()]
used_covering = {
    name for name in covering_indexes
    if any("COVERING INDEX" in detail.upper() and name.upper() in detail.upper()
           for detail in actual_plan_details)
}
assert used_covering, "SQLite's analytical query plan does not use a submitted covering index."
conn.close()

# Preserve and strengthen the query-plan output assertion.
assert os.path.isfile(PLAN), f"Query plan output file {PLAN} does not exist."
with open(PLAN, "r", encoding="utf-8") as f:
    plan_text = f.read()
plan_upper = plan_text.upper()
assert "SCAN" in plan_upper or "SEARCH" in plan_upper or "USING" in plan_upper, \
    f"File {PLAN} does not seem to contain valid EXPLAIN QUERY PLAN output."
assert any(name.upper() in plan_upper for name in used_covering), \
    "query_plan.txt does not show the covering index used by the analytical query."
assert "COVERING INDEX" in plan_upper, "query_plan.txt does not show covering-index usage."
assert len([line for line in plan_text.splitlines() if line.strip()]) >= 2, \
    "query_plan.txt does not contain the rows of a real query plan."

# Validate the report against results retained from the pristine challenge data.
assert os.path.isfile(REPORT), f"Report file {REPORT} does not exist."
with open(REPORT, "r", encoding="utf-8", newline="") as f:
    actual_rows = [row for row in csv.reader(f) if row]
assert actual_rows, f"File {REPORT} is empty."
assert actual_rows[0] == ["user_name", "total_volume", "avg_amount"], \
    "The CSV header must be exactly user_name,total_volume,avg_amount."
data_rows = actual_rows[1:]
assert len(data_rows) == len(expected_rows) == 5, \
    f"Expected 5 data rows, but found {len(data_rows)}."
number_2dp = re.compile(r"^-?\d+\.\d{2}$")
for i, (actual, expected) in enumerate(zip(data_rows, expected_rows), 1):
    assert len(actual) == 3, f"Row {i} does not contain exactly three columns."
    expected_name = expected[0]
    expected_total = f"{expected[1]:.2f}"
    expected_avg = f"{expected[2]:.2f}"
    assert actual[0] == expected_name, f"Row {i}: Expected user_name {expected_name!r}, got {actual[0]!r}."
    assert number_2dp.fullmatch(actual[1]), f"Row {i}: total_volume is not formatted to 2 decimal places."
    assert number_2dp.fullmatch(actual[2]), f"Row {i}: avg_amount is not formatted to 2 decimal places."
    assert actual[1] == expected_total, f"Row {i}: Expected total_volume {expected_total!r}, got {actual[1]!r}."
    assert actual[2] == expected_avg, f"Row {i}: Expected avg_amount {expected_avg!r}, got {actual[2]!r}."
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
