#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import shutil
import sqlite3
import subprocess
import uuid

SCRIPT_PATH = "/home/user/report.sh"
DB_PATH = "/home/user/company.db"
HEADER = ["Employee", "Department", "TotalSales", "DeptRank"]


def run_script(args):
    return subprocess.run([SCRIPT_PATH] + args, capture_output=True, text=True, timeout=20)


def check_csv_content(file_path, expected_rows):
    with open(file_path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "CSV file is empty"
    assert rows[0] == expected_rows[0], f"Header mismatch. Expected {expected_rows[0]}, got {rows[0]}"
    assert len(rows) == len(expected_rows), f"Row count mismatch. Expected {len(expected_rows)} rows, got {len(rows)}"

    for i in range(1, len(rows)):
        assert len(rows[i]) == 4, f"Row {i} must contain exactly four CSV columns, got {rows[i]}"
        assert rows[i][0] == expected_rows[i][0], f"Row {i} Employee mismatch. Expected {expected_rows[i][0]}, got {rows[i][0]}"
        assert rows[i][1] == expected_rows[i][1], f"Row {i} Department mismatch. Expected {expected_rows[i][1]}, got {rows[i][1]}"
        assert float(rows[i][2]) == float(expected_rows[i][2]), f"Row {i} TotalSales mismatch. Expected {expected_rows[i][2]}, got {rows[i][2]}"
        assert int(rows[i][3]) == int(expected_rows[i][3]), f"Row {i} DeptRank mismatch. Expected {expected_rows[i][3]}, got {rows[i][3]}"


def test_report_sh_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"{SCRIPT_PATH} is missing"
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable"


def test_report_all_departments():
    out_file = "/home/user/out_all.csv"
    if os.path.exists(out_file):
        os.remove(out_file)

    res = run_script(["ALL", "10", "0", out_file])
    assert res.returncode == 0, f"Script failed with error: {res.stderr}"
    assert os.path.exists(out_file), f"Output file {out_file} was not created"

    expected = [
        ["Employee", "Department", "TotalSales", "DeptRank"],
        ["Eve", "Clothing", "450.0", "1"],
        ["David", "Clothing", "150.0", "2"],
        ["Bob", "Electronics", "1000.0", "1"],
        ["Alice", "Electronics", "800.0", "2"],
        ["Charlie", "Electronics", "200.0", "3"],
        ["Frank", "Home", "900.0", "1"]
    ]

    check_csv_content(out_file, expected)


def test_report_specific_department_with_pagination():
    out_file = "/home/user/out_dept1.csv"
    if os.path.exists(out_file):
        os.remove(out_file)

    res = run_script(["1", "2", "1", out_file])
    assert res.returncode == 0, f"Script failed with error: {res.stderr}"
    assert os.path.exists(out_file), f"Output file {out_file} was not created"

    expected = [
        ["Employee", "Department", "TotalSales", "DeptRank"],
        ["Alice", "Electronics", "800.0", "2"],
        ["Charlie", "Electronics", "200.0", "3"]
    ]

    check_csv_content(out_file, expected)


def test_rejects_argument_counts_other_than_four():
    token = uuid.uuid4().hex
    out_file = f"/home/user/bad_args_{token}.csv"
    bad_argument_lists = [
        [],
        ["ALL"],
        ["ALL", "2"],
        ["ALL", "2", "0"],
        ["ALL", "2", "0", out_file, "extra"],
        ["ALL", "2", "0", out_file, "extra", "extra2"],
    ]
    for args in bad_argument_lists:
        res = run_script(args)
        assert res.returncode != 0, f"Script accepted {len(args)} arguments; exactly four are required"


def independently_expected(conn, dept_filter, limit, offset):
    departments = dict(conn.execute("SELECT id, name FROM departments").fetchall())
    employees = conn.execute("SELECT id, dept_id, name FROM employees").fetchall()

    totals = {}
    for emp_id, amount in conn.execute("SELECT emp_id, amount FROM sales").fetchall():
        totals[emp_id] = totals.get(emp_id, 0.0) + float(amount)

    grouped = {}
    for emp_id, dept_id, employee_name in employees:
        if emp_id not in totals:
            continue
        if dept_filter != "ALL" and dept_id != int(dept_filter):
            continue
        grouped.setdefault(dept_id, []).append((employee_name, totals[emp_id]))

    result = []
    for dept_id, people in grouped.items():
        by_sales = sorted(people, key=lambda item: -item[1])
        previous_total = None
        previous_rank = None
        ranked = []
        for position, (employee_name, total) in enumerate(by_sales, start=1):
            if previous_total is None or total != previous_total:
                previous_rank = position
                previous_total = total
            ranked.append((employee_name, departments[dept_id], total, previous_rank))
        result.extend(ranked)

    result.sort(key=lambda row: (row[1], row[3], row[0]))
    result = result[offset:offset + limit]
    return [HEADER] + [[row[0], row[1], str(row[2]), str(row[3])] for row in result]


def test_z_randomized_database_filtering_ranking_and_pagination():
    backup = f"/tmp/company_backup_{uuid.uuid4().hex}.db"
    shutil.copy2(DB_PATH, backup)
    token = uuid.uuid4().hex[:10]

    try:
        conn = sqlite3.connect(DB_PATH)
        max_dept = conn.execute("SELECT COALESCE(MAX(id), 0) FROM departments").fetchone()[0]
        max_emp = conn.execute("SELECT COALESCE(MAX(id), 0) FROM employees").fetchone()[0]
        max_sale = conn.execute("SELECT COALESCE(MAX(id), 0) FROM sales").fetchone()[0]

        dept_a = max_dept + random.randint(20, 100)
        dept_b = dept_a + random.randint(20, 100)
        dept_a_name = f"Dynamic-{token}-North"
        dept_b_name = f"Dynamic-{token}-South"
        conn.executemany("INSERT INTO departments(id, name) VALUES (?, ?)", [
            (dept_a, dept_a_name), (dept_b, dept_b_name)
        ])

        employee_rows = [
            (max_emp + 11, dept_a, f"Ada-{token}"),
            (max_emp + 12, dept_a, f"Bea-{token}"),
            (max_emp + 13, dept_a, f"Cy-{token}"),
            (max_emp + 14, dept_a, f"NoSale-{token}"),
            (max_emp + 21, dept_b, f"Di-{token}"),
            (max_emp + 22, dept_b, f"Eli-{token}"),
        ]
        conn.executemany("INSERT INTO employees(id, dept_id, name) VALUES (?, ?, ?)", employee_rows)

        high = float(random.randint(700, 1300))
        low = float(random.randint(100, 400))
        other_high = float(random.randint(1400, 1900))
        sales_rows = [
            (max_sale + 11, max_emp + 11, high / 2),
            (max_sale + 12, max_emp + 11, high / 2),
            (max_sale + 13, max_emp + 12, high),
            (max_sale + 14, max_emp + 13, low),
            (max_sale + 15, max_emp + 21, other_high),
            (max_sale + 16, max_emp + 22, low + 1),
        ]
        conn.executemany("INSERT INTO sales(id, emp_id, amount) VALUES (?, ?, ?)", sales_rows)
        conn.commit()

        cases = [
            (str(dept_a), random.randint(2, 4), random.randint(0, 1)),
            (str(dept_b), random.randint(1, 3), 0),
            ("ALL", random.randint(4, 8), random.randint(1, 4)),
        ]

        for index, (dept_filter, limit, offset) in enumerate(cases):
            out_file = f"/home/user/dynamic_{token}_{index}.csv"
            if os.path.exists(out_file):
                os.remove(out_file)
            expected = independently_expected(conn, dept_filter, limit, offset)
            res = run_script([dept_filter, str(limit), str(offset), out_file])
            assert res.returncode == 0, f"Dynamic invocation failed: {res.stderr}"
            assert os.path.exists(out_file), f"Output file {out_file} was not created"
            check_csv_content(out_file, expected)

        conn.close()
    finally:
        try:
            conn.close()
        except Exception:
            pass
        shutil.copy2(backup, DB_PATH)
        os.remove(backup)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
