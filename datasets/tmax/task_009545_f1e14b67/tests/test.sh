#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

SOURCE = "/home/user/audit_report.c"
EXECUTABLE = "/home/user/audit_report"
DATABASE = "/home/user/audit.db"
REPORT = "/home/user/compliance_report.csv"

EXPECTED_ORIGINAL = [
    "Department Head,Employee,System Name,Risk Level,Rank",
    "Alice Smith,Bob Jones,AWS Prod,9,1",
    "Alice Smith,Charlie Brown,Jenkins,9,2",
    "Diana Prince,Evan Wright,Payroll System,10,1",
    "Diana Prince,Diana Prince,Stripe,8,2",
]


def test_c_source_file_exists():
    path = SOURCE
    assert os.path.isfile(path), f"The C source file was not found at {path}"


def test_executable_exists():
    path = EXECUTABLE
    assert os.path.isfile(path), f"The compiled executable was not found at {path}"
    assert os.access(path, os.X_OK), f"The file at {path} is not executable"


def test_csv_report_exists():
    path = REPORT
    assert os.path.isfile(path), f"The compliance report CSV was not found at {path}"


def test_csv_report_contents():
    path = REPORT
    assert os.path.isfile(path), f"The compliance report CSV was not found at {path}"
    with open(path, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == EXPECTED_ORIGINAL, (
        f"CSV contents do not match expected output.\n"
        f"Expected: {EXPECTED_ORIGINAL}\nActual: {actual_lines}"
    )


def source_text_for_checks():
    with open(SOURCE, "r", encoding="utf-8") as f:
        source = f.read()
    no_comments = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    no_comments = re.sub(r"//[^\n]*", " ", no_comments)
    literals = []
    for token in re.findall(r'"(?:\\.|[^"\\])*"', no_comments, flags=re.S):
        try:
            literals.append(ast.literal_eval(token))
        except Exception:
            pass
    return no_comments, no_comments + "\n" + "".join(literals) + "\n" + " ".join(literals)


def assert_required_c_and_sql():
    source, searchable = source_text_for_checks()
    low_source = source.lower()
    low = searchable.lower()

    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", source), \
        "The C source must include sqlite3.h"
    assert re.search(r"\bsqlite3_open(?:_v2)?\s*\(", low_source), \
        "The program must open the database through the SQLite C API"
    executes_sql = (
        (re.search(r"\bsqlite3_prepare(?:_v2|_v3)?\s*\(", low_source) and
         re.search(r"\bsqlite3_step\s*\(", low_source))
        or re.search(r"\bsqlite3_exec\s*\(", low_source)
        or re.search(r"\bsqlite3_get_table\s*\(", low_source)
    )
    assert executes_sql, "The program must execute its query through the SQLite C API"
    assert re.search(r"\bwith\s+recursive\b", low), \
        "The executed SQL must contain a recursive CTE"
    assert re.search(r"\b(row_number|rank|dense_rank)\s*\([^)]*\)\s*over\s*\(", low, re.S), \
        "The executed SQL must contain a ranking window function"
    assert re.search(r"risk_level\b.{0,120}\bdesc\b.{0,500}system_name\b.{0,120}\basc\b", low, re.S), \
        "The window ordering must use risk_level DESC and system_name ASC"


def compile_submission():
    result = subprocess.run(
        ["gcc", SOURCE, "-o", EXECUTABLE, "-lsqlite3"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"The submitted C source did not compile:\n{result.stderr}"
    test_executable_exists()
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The generated audit_report is not a compiled ELF executable"


def run_report():
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        [EXECUTABLE], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"audit_report exited with status {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(REPORT), "audit_report did not generate compliance_report.csv"


def install_dynamic_database(tag):
    heads = [f"HeadA_{tag}", f"HeadB_{tag}"]
    employees = [
        (101, heads[0], None, "DeptA"),
        (102, f"WorkerA_{tag}", 101, "DeptA"),
        (103, f"DeepA_{tag}", 102, "DeptA"),
        (104, f"OtherA_{tag}", 101, "DeptA"),
        (201, heads[1], None, "DeptB"),
        (202, f"WorkerB_{tag}", 201, "DeptB"),
        (203, f"DeepB_{tag}", 202, "DeptB"),
    ]
    accesses = [
        (101, f"Low_{tag}", 1),
        (102, f"Zulu_{tag}", 91),
        (103, f"Alpha_{tag}", 91),
        (104, f"Middle_{tag}", 70),
        (201, f"HeadSystem_{tag}", 42),
        (202, f"Critical_{tag}", 99),
        (203, f"Second_{tag}", 88),
        (203, f"Third_{tag}", 30),
    ]

    if os.path.exists(DATABASE):
        os.remove(DATABASE)
    con = sqlite3.connect(DATABASE)
    try:
        con.executescript("""
            CREATE TABLE employees(id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, department TEXT);
            CREATE TABLE access(employee_id INTEGER, system_name TEXT, risk_level INTEGER);
        """)
        con.executemany("INSERT INTO employees VALUES (?, ?, ?, ?)", employees)
        con.executemany("INSERT INTO access VALUES (?, ?, ?)", accesses)
        con.commit()
    finally:
        con.close()

    by_id = {row[0]: row for row in employees}
    head_for = {}
    for employee_id, _, _, _ in employees:
        current = employee_id
        while by_id[current][2] is not None:
            current = by_id[current][2]
        head_for[employee_id] = by_id[current][1]

    grouped = {}
    names = {row[0]: row[1] for row in employees}
    for employee_id, system, risk in accesses:
        grouped.setdefault(head_for[employee_id], []).append(
            (employee_id, names[employee_id], system, risk)
        )

    rows = []
    for head, entries in grouped.items():
        ordered = sorted(entries, key=lambda x: (-x[3], x[2]))
        for rank, (_, employee, system, risk) in enumerate(ordered, 1):
            if rank <= 2:
                rows.append([head, employee, system, str(risk), str(rank)])
    rows.sort(key=lambda row: (row[0], int(row[4]), row[1]))
    return [["Department Head", "Employee", "System Name", "Risk Level", "Rank"]] + rows


def assert_dynamic_report(expected):
    with open(REPORT, "rb") as f:
        raw = f.read()
    assert raw.endswith(b"\n"), "The CSV report must be newline-terminated"
    with open(REPORT, "r", encoding="utf-8", newline="") as f:
        actual = list(csv.reader(f))
    assert actual == expected, f"Dynamic database report was incorrect.\nExpected: {expected}\nActual: {actual}"


def test_complete_submission():
    test_c_source_file_exists()
    test_executable_exists()
    assert_required_c_and_sql()
    compile_submission()

    run_report()
    test_csv_report_exists()
    test_csv_report_contents()

    backup_dir = tempfile.mkdtemp(prefix="audit-verifier-")
    backup_db = os.path.join(backup_dir, "audit.db")
    shutil.copy2(DATABASE, backup_db)
    try:
        tag = uuid.uuid4().hex[:10]
        expected = install_dynamic_database(tag)
        run_report()
        assert_dynamic_report(expected)
    finally:
        shutil.copy2(backup_db, DATABASE)
        shutil.rmtree(backup_dir)
        if os.path.isfile(EXECUTABLE):
            subprocess.run([EXECUTABLE], cwd="/home/user", stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=20, check=False)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
