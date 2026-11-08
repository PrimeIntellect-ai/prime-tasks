#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import subprocess

CPP_PATH = "/home/user/auditor.cpp"
BIN_PATH = "/home/user/auditor"
CSV_PATH = "/home/user/audit_report.csv"
DB_PATH = "/home/user/audit.db"
REBUILT_PATH = "/tmp/auditor_rebuilt"
BACKUP_PATH = "/tmp/audit.db.original"

ORIGINAL_EMPLOYEES = [
    (1, "Alice", None, "Exec"),
    (2, "Bob", 1, "Sales"),
    (3, "Charlie", 1, "Engineering"),
    (4, "Dave", 2, "Sales"),
    (5, "Eve", 2, "Sales"),
    (6, "Frank", 3, "Engineering"),
    (7, "Grace", 3, "Engineering"),
]
ORIGINAL_TRANSACTIONS = [
    (101, 4, 100.0, "2023-01-01"),
    (102, 4, 150.0, "2023-01-02"),
    (103, 5, 120.0, "2023-01-03"),
    (104, 5, 1500.0, "2023-01-04"),
    (105, 6, 200.0, "2023-01-01"),
    (106, 6, 250.0, "2023-01-02"),
    (107, 7, 300.0, "2023-01-03"),
    (108, 7, 3000.0, "2023-01-05"),
]
ORIGINAL_CSV = """tx_id,emp_name,amount,top_manager_name
104,Eve,1500.0,Alice
108,Grace,3000.0,Alice
"""


def assert_artifacts_exist():
    assert os.path.exists(CPP_PATH), f"Source file {CPP_PATH} does not exist."
    assert os.path.isfile(CPP_PATH), f"Path {CPP_PATH} is not a file."
    assert os.path.exists(BIN_PATH), f"Compiled binary {BIN_PATH} does not exist."
    assert os.path.isfile(BIN_PATH), f"Path {BIN_PATH} is not a file."
    assert os.access(BIN_PATH, os.X_OK), f"Binary {BIN_PATH} is not executable."
    with open(BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The submitted auditor is not a compiled executable."


def assert_required_sql_is_present():
    with open(CPP_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert re.search(r"\bover\b", source, re.IGNORECASE), "No SQL window-function OVER clause was found."
    assert re.search(r"\bwith\s+recursive\b", source, re.IGNORECASE), "No WITH RECURSIVE hierarchy query was found."


def read_db():
    conn = sqlite3.connect(DB_PATH)
    try:
        objects = conn.execute(
            "SELECT type, name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"
        ).fetchall()
        employees = conn.execute(
            "SELECT emp_id, name, manager_id, department FROM employees ORDER BY emp_id"
        ).fetchall()
        transactions = conn.execute(
            "SELECT tx_id, emp_id, amount, tx_date FROM transactions ORDER BY tx_id"
        ).fetchall()
        return objects, employees, transactions
    finally:
        conn.close()


def assert_db_equals(employees, transactions):
    objects, actual_employees, actual_transactions = read_db()
    assert objects == [("table", "employees"), ("table", "transactions")], "Database schema objects were modified."
    assert actual_employees == sorted(employees), "Employees table contents were modified."
    assert actual_transactions == sorted(transactions), "Transactions table contents were modified."
    assert len(actual_employees) == len(employees)
    assert len(actual_transactions) == len(transactions)


def install_db(employees, transactions):
    for suffix in ("", "-wal", "-shm", "-journal"):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executescript("""
            CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, department TEXT);
            CREATE TABLE transactions (tx_id INTEGER PRIMARY KEY, emp_id INTEGER, amount REAL, tx_date TEXT);
        """)
        conn.executemany("INSERT INTO employees VALUES (?, ?, ?, ?)", employees)
        conn.executemany("INSERT INTO transactions VALUES (?, ?, ?, ?)", transactions)
        conn.commit()
    finally:
        conn.close()


def expected_csv(employees, transactions):
    by_id = {row[0]: row for row in employees}
    department_amounts = {}
    for _, emp_id, amount, _ in transactions:
        department = by_id[emp_id][3]
        department_amounts.setdefault(department, []).append(float(amount))
    averages = {d: sum(values) / len(values) for d, values in department_amounts.items()}

    rows = []
    for tx_id, emp_id, amount, _ in transactions:
        employee = by_id[emp_id]
        if float(amount) <= 3.0 * averages[employee[3]]:
            continue
        top = employee
        seen = set()
        while top[2] is not None:
            assert top[0] not in seen, "Verifier scenario unexpectedly contains a management cycle."
            seen.add(top[0])
            top = by_id[top[2]]
        value = float(amount)
        amount_text = f"{value:.1f}" if value.is_integer() else str(value)
        rows.append((tx_id, employee[1], amount_text, top[1]))

    rows.sort(key=lambda row: row[0])
    result = "tx_id,emp_name,amount,top_manager_name\n"
    result += "".join(f"{tx},{name},{amount},{manager}\n" for tx, name, amount, manager in rows)
    return result


def run_and_check(executable, employees, transactions, expected):
    try:
        os.remove(CSV_PATH)
    except FileNotFoundError:
        pass
    result = subprocess.run(
        [executable], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(CSV_PATH), f"CSV report {CSV_PATH} does not exist after executing {executable}."
    assert os.path.isfile(CSV_PATH), f"Path {CSV_PATH} is not a file."
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        content = f.read().replace("\r\n", "\n")
    assert content.strip() == expected.strip(), (
        f"CSV content from {executable} does not match expected output.\n"
        f"Expected:\n{expected}\nGot:\n{content}"
    )
    assert_db_equals(employees, transactions)


def make_random_scenario():
    token = secrets.token_hex(5)
    base_emp = 1000 + secrets.randbelow(500000)
    ids = [base_emp + i * 7 for i in range(1, 9)]
    employees = [
        (ids[0], f"CEO_{token}", None, "Exec"),
        (ids[1], f"SalesMgr_{token}", ids[0], "Sales"),
        (ids[2], f"SalesLead_{token}", ids[1], "Sales"),
        (ids[3], f"SalesA_{token}", ids[2], "Sales"),
        (ids[4], f"SalesB_{token}", ids[2], "Sales"),
        (ids[5], f"EngMgr_{token}", ids[0], "Engineering"),
        (ids[6], f"EngA_{token}", ids[5], "Engineering"),
        (ids[7], f"EngB_{token}", ids[5], "Engineering"),
    ]
    tx_base = 10000 + secrets.randbelow(800000)
    high = float(1000 + secrets.randbelow(700))
    raw = [
        (tx_base + 51, ids[3], 10.0),
        (tx_base + 7, ids[3], 20.0),
        (tx_base + 83, ids[4], 30.0),
        (tx_base + 12, ids[4], 40.0),
        (tx_base + 68, ids[3], 50.0),
        (tx_base + 29, ids[4], high),
        (tx_base + 91, ids[6], 10.0),
        (tx_base + 3, ids[6], 10.0),
        (tx_base + 44, ids[7], 10.0),
        (tx_base + 76, ids[7], 90.0),
    ]
    transactions = [
        (tx_id, emp_id, amount, f"2025-02-{index + 1:02d}")
        for index, (tx_id, emp_id, amount) in enumerate(raw)
    ]
    return employees, transactions


def test_complete_solution():
    assert_artifacts_exist()
    assert_required_sql_is_present()
    assert_db_equals(ORIGINAL_EMPLOYEES, ORIGINAL_TRANSACTIONS)
    shutil.copy2(DB_PATH, BACKUP_PATH)

    try:
        compile_result = subprocess.run(
            ["g++", "-std=c++17", CPP_PATH, "-o", REBUILT_PATH, "-lsqlite3"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
        )
        assert compile_result.returncode == 0, (
            f"auditor.cpp did not compile.\nstdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
        )

        run_and_check(BIN_PATH, ORIGINAL_EMPLOYEES, ORIGINAL_TRANSACTIONS, ORIGINAL_CSV)
        run_and_check(REBUILT_PATH, ORIGINAL_EMPLOYEES, ORIGINAL_TRANSACTIONS, ORIGINAL_CSV)

        for _ in range(2):
            employees, transactions = make_random_scenario()
            install_db(employees, transactions)
            expected = expected_csv(employees, transactions)
            run_and_check(BIN_PATH, employees, transactions, expected)
            run_and_check(REBUILT_PATH, employees, transactions, expected)
    finally:
        for suffix in ("", "-wal", "-shm", "-journal"):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        shutil.copy2(BACKUP_PATH, DB_PATH)

    assert_db_equals(ORIGINAL_EMPLOYEES, ORIGINAL_TRANSACTIONS)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
