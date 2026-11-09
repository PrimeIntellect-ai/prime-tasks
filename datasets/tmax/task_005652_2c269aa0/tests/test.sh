#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import shutil
import sqlite3
import subprocess

SOURCE_PATH = "/home/user/extractor.cpp"
EXE_PATH = "/home/user/extractor"
DB_PATH = "/home/user/audit.db"
CSV_PATH = "/home/user/audit_report.csv"

BASELINE = r'''#include <iostream>
#include <fstream>
#include <sqlite3.h>
#include <string>

static int callback(void* data, int argc, char** argv, char** azColName) {
    std::ofstream* outFile = static_cast<std::ofstream*>(data);
    for (int i = 0; i < argc; i++) {
        *outFile << (argv[i] ? argv[i] : "NULL");
        if (i < argc - 1) *outFile << ",";
    }
    *outFile << "\n";
    return 0;
}

int main() {
    sqlite3* db;
    char* zErrMsg = 0;
    int rc;

    rc = sqlite3_open("/home/user/audit.db", &db);
    if (rc) {
        std::cerr << "Can't open database: " << sqlite3_errmsg(db) << "\n";
        return(0);
    }

    std::ofstream outFile("/home/user/audit_report.csv");
    outFile << "Name,Department,Resource,Timestamp\n";

    // BUG: Missing JOIN condition (implicit cross join)
    std::string sql = "SELECT employees.name, employees.department, access_logs.resource, access_logs.timestamp "
                      "FROM employees, access_logs "
                      "WHERE access_logs.status = 'DENIED' "
                      "ORDER BY access_logs.timestamp DESC LIMIT 10;";

    rc = sqlite3_exec(db, sql.c_str(), callback, &outFile, &zErrMsg);

    if (rc != SQLITE_OK) {
        std::cerr << "SQL error: " << zErrMsg << "\n";
        sqlite3_free(zErrMsg);
    }

    outFile.close();
    sqlite3_close(db);
    return 0;
}
'''

EXPECTED_QUERY = """
    SELECT employees.name, employees.department, access_logs.resource, access_logs.timestamp
    FROM employees
    JOIN access_logs ON employees.id = access_logs.employee_id
    WHERE access_logs.status = 'DENIED'
    ORDER BY access_logs.timestamp DESC
    LIMIT 10;
"""


def expected_rows():
    conn = sqlite3.connect(DB_PATH)
    try:
        return conn.execute(EXPECTED_QUERY).fetchall()
    finally:
        conn.close()


def read_report():
    with open(CSV_PATH, "r", newline="") as f:
        return list(csv.reader(f))


def run_extractor():
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run([EXE_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert result.returncode == 0, f"Extractor failed with code {result.returncode}: {result.stderr}"
    assert os.path.exists(CSV_PATH), "Running /home/user/extractor did not generate audit_report.csv"


def test_extractor_executable_exists():
    exe_path = "/home/user/extractor"
    assert os.path.exists(exe_path), f"The compiled executable {exe_path} does not exist. Did you compile the C++ code?"
    assert os.access(exe_path, os.X_OK), f"The file {exe_path} is not executable."


def test_only_query_changed_and_compiled_program_works():
    assert os.path.isfile(SOURCE_PATH), f"The source file {SOURCE_PATH} is missing."
    with open(SOURCE_PATH, "r") as f:
        source = f.read()

    start_marker = "    std::string sql = "
    end_marker = "\n\n    rc = sqlite3_exec"
    base_start = BASELINE.index(start_marker)
    base_end = BASELINE.index(end_marker, base_start)
    src_start = source.index(start_marker)
    src_end = source.index(end_marker, src_start)

    assert source[:src_start] == BASELINE[:base_start], "Code before the SQL query was changed; only the SQL query string may be modified."
    assert source[src_end:] == BASELINE[base_end:], "Code after the SQL query was changed; only the SQL query string may be modified."

    query_block = source[src_start:src_end]
    literal_assignment = r'    std::string sql =\s*(?:"(?:\\.|[^"\\])*"\s*)+;'
    assert re.fullmatch(literal_assignment, query_block), "The SQL assignment must remain a string-literal assignment."

    rebuilt = "/tmp/extractor_rebuilt"
    build = subprocess.run(
        ["g++", SOURCE_PATH, "-o", rebuilt, "-lsqlite3"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert build.returncode == 0, f"extractor.cpp does not compile with the required command: {build.stderr}"
    with open(EXE_PATH, "rb") as submitted, open(rebuilt, "rb") as verified:
        assert submitted.read() == verified.read(), "/home/user/extractor was not compiled from the submitted extractor.cpp with the required command."

    backup = "/tmp/audit.db.original"
    shutil.copy2(DB_PATH, backup)
    token = secrets.token_hex(8)
    try:
        conn = sqlite3.connect(DB_PATH)
        try:
            first_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 100 FROM employees").fetchone()[0]
            log_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 100 FROM access_logs").fetchone()[0]
            for offset in range(3):
                conn.execute(
                    "INSERT INTO employees(id, name, department) VALUES (?, ?, ?)",
                    (first_id + offset, f"Dynamic-{token}-{offset}", f"Dept-{token}-{offset}"),
                )
            for offset in range(12):
                conn.execute(
                    "INSERT INTO access_logs(id, employee_id, resource, status, timestamp) VALUES (?, ?, ?, 'DENIED', ?)",
                    (log_id + offset, first_id + (offset % 3), f"Resource-{token}-{offset}", f"2099-12-{offset + 1:02d} 12:00:00"),
                )
            conn.execute(
                "INSERT INTO access_logs(id, employee_id, resource, status, timestamp) VALUES (?, ?, ?, 'GRANTED', '2100-01-02 00:00:00')",
                (log_id + 50, first_id, f"Granted-{token}"),
            )
            conn.execute(
                "INSERT INTO access_logs(id, employee_id, resource, status, timestamp) VALUES (?, ?, ?, 'DENIED', '2100-01-03 00:00:00')",
                (log_id + 51, first_id + 99999, f"Orphan-{token}"),
            )
            conn.commit()
        finally:
            conn.close()

        expected = [[str(value) for value in row] for row in expected_rows()]
        run_extractor()
        actual = read_report()
        assert actual and actual[0] == ["Name", "Department", "Resource", "Timestamp"], "Running the extractor produced an incorrect CSV header."
        assert actual[1:] == expected, "Running the compiled extractor on verification data produced incorrect rows."
    finally:
        for suffix in ("-wal", "-shm", "-journal"):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        shutil.copy2(backup, DB_PATH)
        run_extractor()


def test_audit_report_csv_correctness():
    csv_path = "/home/user/audit_report.csv"
    assert os.path.exists(csv_path), f"The output file {csv_path} was not generated."

    db_path = "/home/user/audit.db"
    assert os.path.exists(db_path), f"The database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    query = """
        SELECT employees.name, employees.department, access_logs.resource, access_logs.timestamp
        FROM employees
        JOIN access_logs ON employees.id = access_logs.employee_id
        WHERE access_logs.status = 'DENIED'
        ORDER BY access_logs.timestamp DESC
        LIMIT 10;
    """
    cursor.execute(query)
    expected = cursor.fetchall()
    conn.close()

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        actual_data = list(reader)

    assert len(actual_data) > 0, "The CSV file is empty."

    expected_header = ["Name", "Department", "Resource", "Timestamp"]
    assert actual_data[0] == expected_header, f"CSV header is incorrect. Expected {expected_header}, got {actual_data[0]}"

    actual_rows = actual_data[1:]
    assert len(actual_rows) == len(expected), f"Expected {len(expected)} data rows, but got {len(actual_rows)} rows."

    for i, (actual, expected_row) in enumerate(zip(actual_rows, expected)):
        expected_str_list = [str(item) for item in expected_row]
        assert actual == expected_str_list, f"Row {i+1} mismatch.\nExpected: {expected_str_list}\nGot: {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
