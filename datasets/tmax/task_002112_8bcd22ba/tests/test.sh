#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_audit_task.py
import csv
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

HOME = "/home/user"
DB = os.path.join(HOME, "audit.db")
SOURCE = os.path.join(HOME, "audit_analyzer.c")
INDEX_SQL = os.path.join(HOME, "indexes.sql")
FLAGGED = os.path.join(HOME, "flagged_contractors.txt")
SUMMARY = os.path.join(HOME, "audit_summary.txt")
BINARY = "/tmp/audit_analyzer_verified"


def run_program():
    for path in (FLAGGED, SUMMARY):
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run(
        [BINARY], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"audit_analyzer exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(FLAGGED), f"File {FLAGGED} is missing."
    assert os.path.isfile(SUMMARY), f"File {SUMMARY} is missing."


def check_indexes_sql():
    assert os.path.isfile(INDEX_SQL), f"File {INDEX_SQL} is missing."
    with open(INDEX_SQL, "r", encoding="utf-8") as f:
        content = f.read()
    lowered = content.lower()
    assert "create index" in lowered, "indexes.sql does not contain 'CREATE INDEX'."
    assert "communications" in lowered, "indexes.sql does not reference the 'communications' table."
    assert "sender_id" in lowered or "receiver_id" in lowered, \
        "indexes.sql does not reference sender_id or receiver_id."

    fd, test_db = tempfile.mkstemp(prefix="index_check_", suffix=".db")
    os.close(fd)
    try:
        conn = sqlite3.connect(test_db)
        conn.executescript("""
            CREATE TABLE employees (
                id INTEGER PRIMARY KEY, name TEXT, department TEXT
            );
            CREATE TABLE communications (
                id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER,
                timestamp DATETIME, byte_size INTEGER
            );
        """)
        try:
            conn.executescript(content)
        except sqlite3.Error as exc:
            raise AssertionError(f"indexes.sql is not valid executable SQL: {exc}")

        table = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='communications'"
        ).fetchone()
        assert table is not None, "indexes.sql removed the communications table."

        leading_columns = set()
        for row in conn.execute("PRAGMA index_list('communications')"):
            index_name = row[1]
            quoted = index_name.replace('"', '""')
            columns = list(conn.execute(f'PRAGMA index_info("{quoted}")'))
            if columns:
                leading_columns.add(columns[0][2])
        assert "sender_id" in leading_columns, \
            "indexes.sql does not create a usable index beginning with sender_id."
        assert "receiver_id" in leading_columns, \
            "indexes.sql does not create a usable index beginning with receiver_id."
        conn.close()
    finally:
        if os.path.exists(test_db):
            os.remove(test_db)


def compile_source():
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing."
    with open(SOURCE, "r", encoding="utf-8", errors="replace") as f:
        source_text = f.read()
    assert "sqlite3.h" in source_text, "The C source does not include the SQLite C API header."
    assert re.search(r"\bsqlite3_(?:open|open_v2)\s*\(", source_text), \
        "The C source does not open the database through the SQLite C API."
    assert re.search(r"\bsqlite3_(?:prepare(?:_v2|_v3)?|exec|get_table)\s*\(", source_text), \
        "The C source does not execute queries through the SQLite C API."

    result = subprocess.run(
        ["gcc", SOURCE, "-o", BINARY, "-lsqlite3"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"Failed to compile audit_analyzer.c:\n{result.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), \
        "Compilation did not produce an executable."


def check_original_outputs():
    run_program()
    with open(FLAGGED, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 1, f"Expected exactly 1 flagged contractor, found {len(lines)}."
    assert lines[0] == "2,Bob,4,500", \
        f"Unexpected content in flagged_contractors.txt: {lines[0]}"

    with open(SUMMARY, "r", encoding="utf-8") as f:
        content = f.read().strip()
    expected = "Total Suspicious Contractors: 1\nMax OutDegree: 4"
    normalized = "\n".join(line.strip() for line in content.splitlines() if line.strip())
    assert normalized == expected, f"Unexpected content in audit_summary.txt:\n{content}"


def build_dynamic_database(trial):
    for suffix in ("", "-wal", "-shm"):
        path = DB + suffix
        if os.path.exists(path):
            os.remove(path)

    token = secrets.token_hex(4)
    base = 1000 + trial * 100 + secrets.randbelow(40)
    senders = [base, base + 1, base + 2, base + 3]
    receivers = [base + 20 + i for i in range(7)]

    conn = sqlite3.connect(DB)
    conn.executescript("""
        CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT);
        CREATE TABLE communications (
            id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER,
            timestamp DATETIME, byte_size INTEGER
        );
    """)
    employees = [
        (senders[0], f"Alpha_{token}", "Contractor"),
        (senders[1], f"Beta_{token}", "Contractor"),
        (senders[2], f"Gamma_{token}", "Contractor"),
        (senders[3], f"Lower_{token}", "contractor"),
    ] + [(rid, f"Receiver_{token}_{i}", "Engineering") for i, rid in enumerate(receivers)]
    conn.executemany("INSERT INTO employees(id,name,department) VALUES (?,?,?)", employees)

    rows = []
    size_seed = 17 + secrets.randbelow(100)
    # Alpha: four unique receivers plus a duplicate communication.
    for i, rid in enumerate(receivers[:4]):
        rows.append((senders[0], rid, size_seed + i * 7))
    rows.append((senders[0], receivers[0], size_seed + 61))
    # Beta: exactly three unique receivers, so it must not be flagged.
    for i, rid in enumerate(receivers[:3]):
        rows.append((senders[1], rid, size_seed + 80 + i))
    # Gamma: five unique receivers and must be flagged.
    for i, rid in enumerate(receivers[:5]):
        rows.append((senders[2], rid, size_seed + 120 + i * 3))
    # Lower-case department has six receivers but is not exactly 'Contractor'.
    for i, rid in enumerate(receivers[:6]):
        rows.append((senders[3], rid, size_seed + 200 + i))
    conn.executemany(
        "INSERT INTO communications(sender_id,receiver_id,byte_size) VALUES (?,?,?)", rows
    )
    conn.commit()

    expected = conn.execute("""
        SELECT e.id, e.name, COUNT(DISTINCT c.receiver_id), SUM(c.byte_size)
        FROM employees e JOIN communications c ON c.sender_id = e.id
        WHERE e.department = 'Contractor'
        GROUP BY e.id, e.name
        HAVING COUNT(DISTINCT c.receiver_id) > 3
    """).fetchall()
    conn.close()
    return {(int(a), str(b), int(c), int(d)) for a, b, c, d in expected}


def check_dynamic_output(expected):
    run_program()
    actual = set()
    with open(FLAGGED, "r", encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    assert len(rows) == len(expected), \
        f"Expected {len(expected)} flagged rows, found {len(rows)}."
    for row in rows:
        assert len(row) == 4, f"Flagged CSV row does not have four fields: {row!r}"
        try:
            actual.add((int(row[0]), row[1], int(row[2]), int(row[3])))
        except ValueError as exc:
            raise AssertionError(f"Flagged CSV contains a non-numeric metric: {row!r}") from exc
    assert actual == expected, f"Incorrect flagged contractors. Expected {expected}, got {actual}."

    expected_summary = (
        f"Total Suspicious Contractors: {len(expected)}\n"
        f"Max OutDegree: {max(row[2] for row in expected)}"
    )
    with open(SUMMARY, "r", encoding="utf-8") as f:
        content = f.read().strip()
    normalized = "\n".join(line.strip() for line in content.splitlines() if line.strip())
    assert normalized == expected_summary, \
        f"Incorrect dynamic audit summary. Expected {expected_summary!r}, got {content!r}."


def main():
    assert os.path.isfile(DB), f"Database {DB} is missing."
    db_stat = os.stat(DB)
    fd, db_backup = tempfile.mkstemp(prefix="audit_backup_", suffix=".db")
    os.close(fd)
    backup_conn = sqlite3.connect(db_backup)
    source_conn = sqlite3.connect(DB)
    source_conn.backup(backup_conn)
    source_conn.close()
    backup_conn.close()

    saved_outputs = {}
    for path in (FLAGGED, SUMMARY):
        saved_outputs[path] = open(path, "rb").read() if os.path.isfile(path) else None

    try:
        check_indexes_sql()
        compile_source()
        check_original_outputs()
        for trial in range(2):
            expected = build_dynamic_database(trial)
            check_dynamic_output(expected)
    finally:
        for suffix in ("", "-wal", "-shm"):
            path = DB + suffix
            if os.path.exists(path):
                os.remove(path)
        shutil.copy2(db_backup, DB)
        os.chmod(DB, db_stat.st_mode)
        try:
            os.chown(DB, db_stat.st_uid, db_stat.st_gid)
        except PermissionError:
            pass
        if os.path.exists(db_backup):
            os.remove(db_backup)
        for path, data in saved_outputs.items():
            if os.path.exists(path):
                os.remove(path)
            if data is not None:
                with open(path, "wb") as f:
                    f.write(data)
        if os.path.exists(BINARY):
            os.remove(BINARY)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_audit_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
