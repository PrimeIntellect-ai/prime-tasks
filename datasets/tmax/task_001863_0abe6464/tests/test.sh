#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import sqlite3
import subprocess

import pytest

DB_PATH = "/home/user/audit.db"
C_SOURCE_PATH = "/home/user/audit_processor.c"
EXEC_PATH = "/home/user/audit_processor"
CSV_PATH = "/home/user/audit_results.csv"
VERIFIED_EXEC_PATH = "/tmp/audit_processor_verified"
EXPECTED_HEADER = ["emp_id", "name", "resource_id", "total_bytes", "rank"]


def get_expected_results(db_path, manager_id, threshold):
    """Compute expected results independently from the submitted program."""
    conn = sqlite3.connect(db_path)
    try:
        return conn.execute(
            """
            WITH RECURSIVE subordinates AS (
                SELECT emp_id, name, manager_id
                FROM employees
                WHERE emp_id = ?

                UNION ALL

                SELECT e.emp_id, e.name, e.manager_id
                FROM employees e
                INNER JOIN subordinates s ON e.manager_id = s.emp_id
            ),
            aggregated AS (
                SELECT s.emp_id, s.name, a.resource_id,
                       SUM(a.bytes_transferred) AS total_bytes
                FROM subordinates s
                JOIN access_logs a ON s.emp_id = a.emp_id
                GROUP BY s.emp_id, s.name, a.resource_id
            ),
            ranked AS (
                SELECT emp_id, name, resource_id, total_bytes,
                       ROW_NUMBER() OVER (
                           PARTITION BY resource_id
                           ORDER BY total_bytes DESC, emp_id ASC
                       ) AS rank
                FROM aggregated
            )
            SELECT emp_id, name, resource_id, total_bytes, rank
            FROM ranked
            WHERE total_bytes > ?
            ORDER BY resource_id ASC, rank ASC
            """,
            (manager_id, threshold),
        ).fetchall()
    finally:
        conn.close()


def read_csv_results():
    assert os.path.exists(CSV_PATH), (
        f"Results CSV file {CSV_PATH} is missing. Did the program run successfully?"
    )
    with open(CSV_PATH, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == EXPECTED_HEADER, (
            f"CSV header is incorrect. Expected: {EXPECTED_HEADER}; Actual: {header}"
        )
        rows = []
        for line_number, row in enumerate(reader, start=2):
            if not row:
                continue
            assert len(row) == 5, f"CSV line {line_number} has {len(row)} fields: {row}"
            try:
                rows.append((int(row[0]), row[1], int(row[2]), int(row[3]), int(row[4])))
            except ValueError as exc:
                pytest.fail(f"Data format error in CSV at line {line_number}: {row}: {exc}")
        return rows


def run_and_check(executable, manager_id, threshold):
    try:
        os.remove(CSV_PATH)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        [executable, str(manager_id), str(threshold)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{executable} failed for manager={manager_id}, threshold={threshold}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    actual = read_csv_results()
    expected = get_expected_results(DB_PATH, manager_id, threshold)
    assert actual == expected, (
        f"CSV contents do not match for manager={manager_id}, threshold={threshold}.\n"
        f"Expected: {expected}\nActual:   {actual}"
    )


@pytest.fixture(scope="session")
def verified_executable():
    result = subprocess.run(
        ["gcc", "-o", VERIFIED_EXEC_PATH, C_SOURCE_PATH, "-lsqlite3"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"The submitted C source did not compile with the required command. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    symbols = subprocess.run(
        ["nm", "-D", VERIFIED_EXEC_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=True,
    ).stdout
    for symbol in (
        "sqlite3_open",
        "sqlite3_prepare_v2",
        "sqlite3_bind_int",
        "sqlite3_step",
        "sqlite3_column_",
        "sqlite3_finalize",
        "sqlite3_close",
    ):
        assert symbol in symbols, f"Compiled program does not use required SQLite C API symbol {symbol}"
    return VERIFIED_EXEC_PATH


def test_c_source_exists():
    assert os.path.exists(C_SOURCE_PATH), f"C source file {C_SOURCE_PATH} is missing."
    assert os.path.isfile(C_SOURCE_PATH), f"{C_SOURCE_PATH} is not a regular file."

    source = open(C_SOURCE_PATH, "r", encoding="utf-8").read()
    source_without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", " ", source, flags=re.S)
    for api in ("sqlite3_open", "sqlite3_prepare_v2", "sqlite3_bind_int", "sqlite3_step"):
        assert re.search(r"\b" + re.escape(api) + r"\s*\(", source_without_comments), (
            f"Source does not call required SQLite C API function {api}"
        )
    for construct in ("WITH RECURSIVE", "ROW_NUMBER", "PARTITION BY"):
        words = construct.split()
        pattern = r"\b" + r"\s+".join(map(re.escape, words)) + r"\b"
        assert re.search(pattern, source_without_comments, flags=re.I), (
            f"Source query is missing required SQL construct {construct}"
        )


def test_executable_exists():
    assert os.path.exists(EXEC_PATH), (
        f"Compiled executable {EXEC_PATH} is missing. Did you compile the C program?"
    )
    assert os.path.isfile(EXEC_PATH), f"{EXEC_PATH} is not a regular file."
    assert os.access(EXEC_PATH, os.X_OK), f"{EXEC_PATH} is not executable."
    with open(EXEC_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXEC_PATH} is not a compiled native executable."


def test_csv_results():
    """Execute the requested invocation, then retain the original exact CSV check."""
    run_and_check(EXEC_PATH, 1, 500)


def test_compiled_source_and_dynamic_inputs(verified_executable):
    """Exercise both the delivered executable and a fresh source build on hidden data."""
    conn = sqlite3.connect(DB_PATH)
    employee_ids = []
    log_ids = []
    try:
        while True:
            base = secrets.randbelow(1_000_000_000) + 100_000
            candidate_ids = [base, base + 1, base + 2, base + 3]
            count = conn.execute(
                "SELECT COUNT(*) FROM employees WHERE emp_id IN (?,?,?,?)",
                candidate_ids,
            ).fetchone()[0]
            if count == 0:
                employee_ids = candidate_ids
                break

        root, child, grandchild, outsider = employee_ids
        resource_a = secrets.randbelow(1_000_000_000) + 1000
        resource_b = resource_a + 1
        threshold = secrets.randbelow(600) + 250
        high = threshold + secrets.randbelow(300) + 100
        top = high + secrets.randbelow(300) + 100

        conn.executemany(
            "INSERT INTO employees(emp_id,name,manager_id) VALUES (?,?,?)",
            [
                (root, f"HiddenRoot{root}", None),
                (child, f"HiddenChild{child}", root),
                (grandchild, f"HiddenGrandchild{grandchild}", child),
                (outsider, f"HiddenOutsider{outsider}", None),
            ],
        )
        first_log = conn.execute("SELECT COALESCE(MAX(log_id),0)+1 FROM access_logs").fetchone()[0]
        rows = [
            (first_log, root, resource_a, high),
            (first_log + 1, child, resource_a, high),
            (first_log + 2, grandchild, resource_a, top),
            (first_log + 3, outsider, resource_a, top + 10000),
            (first_log + 4, child, resource_b, threshold // 2),
            (first_log + 5, child, resource_b, threshold - threshold // 2 + 1),
            (first_log + 6, grandchild, resource_b, threshold),
        ]
        log_ids = [row[0] for row in rows]
        conn.executemany(
            "INSERT INTO access_logs(log_id,emp_id,resource_id,bytes_transferred) VALUES (?,?,?,?)",
            rows,
        )
        conn.commit()

        for executable in (EXEC_PATH, verified_executable):
            run_and_check(executable, root, threshold)
            run_and_check(executable, child, threshold)
            run_and_check(executable, grandchild, top - 1)

            for bad_args in ([], [str(root)], [str(root), str(threshold), "extra"]):
                result = subprocess.run(
                    [executable] + bad_args,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=10,
                )
                assert result.returncode != 0, (
                    f"{executable} must reject an argument count other than exactly two"
                )
    finally:
        if log_ids:
            conn.executemany("DELETE FROM access_logs WHERE log_id=?", [(x,) for x in log_ids])
        if employee_ids:
            conn.executemany("DELETE FROM employees WHERE emp_id=?", [(x,) for x in reversed(employee_ids)])
        conn.commit()
        conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
