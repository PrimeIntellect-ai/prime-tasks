#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import sqlite3
import stat
import subprocess
import pytest

DB_PATH = "/home/user/data.db"
SALES_PATH = "/home/user/sales.json"
SUMMARY_PATH = "/home/user/summary.json"
PROGRAM_PATH = "/home/user/etl.go"


def write_fixture(departments, sales):
    for path in (DB_PATH, DB_PATH + "-journal", DB_PATH + "-wal", DB_PATH + "-shm"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    conn = sqlite3.connect(DB_PATH)
    conn.execute("CREATE TABLE departments(id INTEGER PRIMARY KEY, parent_id INTEGER, name TEXT, is_active INTEGER)")
    conn.executemany(
        "INSERT INTO departments(id, parent_id, name, is_active) VALUES (?, ?, ?, ?)",
        departments,
    )
    conn.execute("CREATE INDEX idx_active ON departments(is_active)")
    conn.commit()
    conn.close()

    with open(SALES_PATH, "w") as f:
        json.dump(sales, f)

    os.chmod(DB_PATH, 0o666)
    os.chmod(SALES_PATH, 0o666)
    try:
        os.remove(SUMMARY_PATH)
    except FileNotFoundError:
        pass


def run_etl():
    result = subprocess.run(
        [
            "runuser", "-u", "user", "--", "env",
            "HOME=/home/user",
            "GOCACHE=/home/user/.cache/go-build",
            "GOMODCACHE=/home/user/go/pkg/mod",
            "bash", "-c", "cd /home/user && go run ./etl.go",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, "The Go ETL program failed when executed:\n" + result.stdout


def load_summary():
    assert os.path.isfile(SUMMARY_PATH), f"Output file {SUMMARY_PATH} is missing."
    with open(SUMMARY_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{SUMMARY_PATH} is not a valid JSON file.")


def assert_index_dropped():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    count = conn.execute(
        "SELECT count(*) FROM sqlite_master WHERE type='index' AND name='idx_active'"
    ).fetchone()[0]
    conn.close()
    assert count == 0, "The index 'idx_active' was not dropped from the database."


def derive_expected(departments, sales):
    nodes = {row[0]: {"parent": row[1], "active": row[3]} for row in departments}
    children = {dept_id: [] for dept_id in nodes}
    roots = []
    for dept_id, node in nodes.items():
        if node["parent"] is None:
            roots.append(dept_id)
        elif node["parent"] in children:
            children[node["parent"]].append(dept_id)

    direct = {dept_id: 0 for dept_id in nodes}
    for tx in sales:
        if tx["dept_id"] in direct:
            direct[tx["dept_id"]] += sum(item["price"] for item in tx["items"])

    totals = {}

    def visit(dept_id, ancestors_valid):
        valid = ancestors_valid and nodes[dept_id]["active"] == 1
        if not valid:
            return 0
        total = direct[dept_id]
        for child in children[dept_id]:
            total += visit(child, True)
        totals[dept_id] = total
        return total

    for root in roots:
        visit(root, True)

    return [
        {"dept_id": dept_id, "total_sales": totals[dept_id]}
        for dept_id in sorted(totals)
    ]


def test_program_exists_and_executes_on_original_fixture():
    assert os.path.exists(PROGRAM_PATH), f"Required Go program {PROGRAM_PATH} is missing."
    assert not os.path.islink(PROGRAM_PATH), f"{PROGRAM_PATH} must be a regular Go source file."
    mode = os.stat(PROGRAM_PATH).st_mode
    assert stat.S_ISREG(mode), f"{PROGRAM_PATH} must be a regular Go source file."
    assert os.path.getsize(PROGRAM_PATH) > 0, f"{PROGRAM_PATH} is empty."

    departments = [
        (1, None, "HQ", 1),
        (2, 1, "Engineering", 1),
        (3, 1, "Marketing", 1),
        (4, 2, "Backend", 1),
        (5, 2, "Frontend", 0),
        (6, 4, "API", 1),
        (7, 5, "UI", 1),
    ]
    sales = [
        {"tx_id": "t1", "dept_id": 1, "items": [{"price": 10}]},
        {"tx_id": "t2", "dept_id": 2, "items": [{"price": 20}]},
        {"tx_id": "t3", "dept_id": 3, "items": [{"price": 15}, {"price": 15}]},
        {"tx_id": "t4", "dept_id": 4, "items": [{"price": 40}]},
        {"tx_id": "t5", "dept_id": 5, "items": [{"price": 50}]},
        {"tx_id": "t6", "dept_id": 6, "items": [{"price": 60}]},
        {"tx_id": "t7", "dept_id": 7, "items": [{"price": 70}]},
    ]
    write_fixture(departments, sales)
    run_etl()


def test_index_dropped():
    assert_index_dropped()


def test_summary_json_content():
    data = load_summary()
    expected_data = [
        {"dept_id": 1, "total_sales": 160},
        {"dept_id": 2, "total_sales": 120},
        {"dept_id": 3, "total_sales": 30},
        {"dept_id": 4, "total_sales": 100},
        {"dept_id": 6, "total_sales": 60},
    ]
    assert isinstance(data, list), f"{SUMMARY_PATH} should contain a JSON array."
    assert data == expected_data, f"The contents of {SUMMARY_PATH} do not match the expected output. Got: {data}"


def test_etl_on_fresh_dynamic_fixture():
    departments = [
        (10, None, "North", 1),
        (11, 10, "North-A", 1),
        (12, 10, "North-Disabled", 0),
        (13, 12, "Hidden-Active", 1),
        (14, 11, "North-A-Leaf", 1),
        (15, None, "South", 1),
        (16, 15, "South-Leaf", 1),
        (17, None, "Disabled-Root", 0),
        (18, 17, "Hidden-Root-Child", 1),
        (19, 11, "Disabled-Branch", 0),
        (20, 19, "Hidden-Branch-Child", 1),
    ]

    def price():
        return 3 + secrets.randbelow(997)

    sales = []
    for i, dept_id in enumerate([10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]):
        sales.append({
            "tx_id": f"dynamic-{i}-{secrets.token_hex(4)}",
            "dept_id": dept_id,
            "items": [{"price": price()}, {"price": price()}],
        })
    sales.append({
        "tx_id": "dynamic-extra",
        "dept_id": 14,
        "items": [{"price": price()}],
    })

    expected = derive_expected(departments, sales)
    write_fixture(departments, sales)
    run_etl()
    assert_index_dropped()
    data = load_summary()
    assert isinstance(data, list), f"{SUMMARY_PATH} should contain a JSON array."
    assert data == expected, f"ETL output for the fresh fixture was incorrect. Expected {expected}, got {data}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
