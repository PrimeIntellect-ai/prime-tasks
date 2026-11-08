#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import shutil
import secrets
import subprocess
import sqlite3
import tempfile

SCRIPT_PATH = '/home/user/generate_report.sh'
DB_PATH = '/home/user/company.db'


def run_report(date):
    result = subprocess.run(
        [SCRIPT_PATH, date], capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    return result.stdout.strip()


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_script_contains_required_sql_features():
    with open(SCRIPT_PATH, 'r', encoding='utf-8', errors='replace') as f:
        source = f.read()
    assert re.search(r'\bWITH\s+RECURSIVE\b', source, re.IGNORECASE), \
        "The report script does not contain a recursive SQL query."
    assert re.search(
        r'\b(?:ROW_NUMBER|RANK|DENSE_RANK)\s*\(\s*\)\s*OVER\s*\(',
        source,
        re.IGNORECASE,
    ), "The report script does not calculate Rank with a window function."


def test_database_integrity():
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("PRAGMA integrity_check;")
        result = cursor.fetchone()[0]
        assert result == "ok", f"Database integrity check failed: {result}"

        indexes = cursor.execute("PRAGMA index_list('sales')").fetchall()
        matching = [row for row in indexes if row[1] == 'idx_sales_date']
        assert matching, "Required repaired index idx_sales_date is missing."

        indexed_columns = cursor.execute(
            "PRAGMA index_info('idx_sales_date')"
        ).fetchall()
        assert [row[2] for row in indexed_columns] == ['sale_date'], \
            "idx_sales_date is not an index on sales(sale_date)."

        indexed = cursor.execute(
            "SELECT id, emp_id, amount, sale_date FROM sales INDEXED BY idx_sales_date "
            "WHERE sale_date <= ? ORDER BY sale_date, id",
            ('9999-12-31',),
        ).fetchall()
        unindexed = cursor.execute(
            "SELECT id, emp_id, amount, sale_date FROM sales NOT INDEXED "
            "WHERE sale_date <= ? ORDER BY sale_date, id",
            ('9999-12-31',),
        ).fetchall()
        assert indexed == unindexed, \
            "A query forced through idx_sales_date returns stale or missing rows."

        plan = cursor.execute(
            "EXPLAIN QUERY PLAN SELECT id FROM sales INDEXED BY idx_sales_date "
            "WHERE sale_date <= ?",
            ('9999-12-31',),
        ).fetchall()
        assert any('idx_sales_date' in str(row) for row in plan), \
            "SQLite cannot use idx_sales_date for date queries."
    finally:
        conn.close()


def test_script_output_2023_01_02():
    expected_output = (
        "1,Frank,400,Alice -> Charlie -> Frank\n"
        "2,Dave,250,Alice -> Bob -> Dave\n"
        "3,Eve,200,Alice -> Bob -> Eve"
    )
    output = run_report('2023-01-02')
    assert output == expected_output, f"Output for 2023-01-02 did not match expected.\nExpected:\n{expected_output}\nGot:\n{output}"


def test_script_output_2023_01_03():
    expected_output = (
        "1,Eve,500,Alice -> Bob -> Eve\n"
        "2,Frank,400,Alice -> Charlie -> Frank\n"
        "3,Dave,250,Alice -> Bob -> Dave"
    )
    output = run_report('2023-01-03')
    assert output == expected_output, f"Output for 2023-01-03 did not match expected.\nExpected:\n{expected_output}\nGot:\n{output}"


def expected_report(date):
    conn = sqlite3.connect(DB_PATH)
    try:
        employees = {
            row[0]: (row[1], row[2])
            for row in conn.execute("SELECT id, name, manager_id FROM employees")
        }
        totals = dict(conn.execute(
            "SELECT emp_id, SUM(amount) FROM sales WHERE sale_date <= ? GROUP BY emp_id",
            (date,),
        ))
    finally:
        conn.close()

    def management_chain(emp_id):
        chain = []
        seen = set()
        current = emp_id
        while current is not None:
            assert current in employees, f"Employee {current} has an invalid manager chain"
            assert current not in seen, "Cycle found in employee hierarchy"
            seen.add(current)
            name, current = employees[current]
            chain.append(name)
        return ' -> '.join(reversed(chain))

    rows = [
        (total, employees[emp_id][0], management_chain(emp_id))
        for emp_id, total in totals.items()
    ]
    rows.sort(key=lambda row: (-row[0], row[1]))
    return '\n'.join(
        f"{rank},{name},{total},{chain}"
        for rank, (total, name, chain) in enumerate(rows[:3], 1)
    )


def test_report_uses_live_database_for_unpredictable_dates_and_rows():
    backup_fd, backup_path = tempfile.mkstemp(prefix='company-backup-', suffix='.db')
    os.close(backup_fd)
    shutil.copy2(DB_PATH, backup_path)

    token = secrets.token_hex(6)
    year = 2035 + secrets.randbelow(40)
    before_date = f'{year}-06-14'
    target_date = f'{year}-06-15'
    future_date = f'{year}-06-16'
    base = 10000 + secrets.randbelow(5000)

    try:
        conn = sqlite3.connect(DB_PATH)
        try:
            next_emp = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM employees").fetchone()[0]
            next_sale = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM sales").fetchone()[0]
            employee_rows = [
                (next_emp, f'DynManager_{token}', 7),
                (next_emp + 1, f'DynAlpha_{token}', next_emp),
                (next_emp + 2, f'DynBeta_{token}', 4),
                (next_emp + 3, f'DynGamma_{token}', next_emp + 2),
            ]
            conn.executemany(
                "INSERT INTO employees(id, name, manager_id) VALUES (?, ?, ?)",
                employee_rows,
            )
            sales_rows = [
                (next_sale, next_emp + 1, 5000, before_date),
                (next_sale + 1, next_emp + 1, base - 4500, target_date),
                (next_sale + 2, next_emp + 2, base + 500, target_date),
                (next_sale + 3, next_emp + 3, base + 200, before_date),
                (next_sale + 4, next_emp + 3, 1000, future_date),
            ]
            conn.executemany(
                "INSERT INTO sales(id, emp_id, amount, sale_date) VALUES (?, ?, ?, ?)",
                sales_rows,
            )
            conn.commit()
        finally:
            conn.close()

        for date in (target_date, future_date):
            expected = expected_report(date)
            output = run_report(date)
            assert output == expected, \
                f"Output for live database date {date} did not match.\nExpected:\n{expected}\nGot:\n{output}"
    finally:
        for suffix in ('-wal', '-shm'):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        os.replace(backup_path, DB_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
