#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import sqlite3
import struct
import subprocess
import secrets
import pytest

TICKET_DIR = "/home/user/ticket_402"
PARSER_C = os.path.join(TICKET_DIR, "parser.c")
FS_DUMP = os.path.join(TICKET_DIR, "fs_dump.bin")
FINAL_RESULT = os.path.join(TICKET_DIR, "final_result.txt")
COMPANY_DB = os.path.join(TICKET_DIR, "company.db")
RECOVERED_SQL = os.path.join(TICKET_DIR, "recovered_query.sql")
ORIGINAL_SQL = b"SELECT username FROM employees WHERE role = 'admin';"


def read_source():
    assert os.path.isfile(PARSER_C), f"{PARSER_C} is missing."
    with open(PARSER_C, "r", encoding="utf-8") as f:
        return f.read()


@pytest.fixture(scope="session")
def parser_exe(tmp_path_factory):
    out = tmp_path_factory.mktemp("build") / "parser"
    result = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", PARSER_C, "-o", str(out)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"parser.c did not compile:\n{result.stderr}"
    assert out.is_file() and os.access(out, os.X_OK)
    return out


def test_parser_c_fixed_loop_counter():
    content = read_source()
    assert "uint8_t i;" not in content, (
        "The loop counter 'i' is still declared as uint8_t, which causes an infinite loop."
    )


def test_parser_c_has_assertion_immediately_after_read():
    content = read_source()
    stripped_content = re.sub(r"\s+", "", content)
    assert "assert(data_len<10000)" in stripped_content or "assert(10000>data_len)" in stripped_content, \
        "The required assertion `assert(data_len < 10000);` was not found in parser.c."

    # Remove comments, then require the assertion to be the next statement after
    # the fread that populates data_len.
    no_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", content, flags=re.S)
    immediate = re.compile(
        r"fread\s*\(\s*&data_len\s*,[^;]*\)\s*;\s*"
        r"assert\s*\(\s*(?:data_len\s*<\s*10000|10000\s*>\s*data_len)\s*\)\s*;",
        flags=re.S,
    )
    assert immediate.search(no_comments), \
        "The data_len assertion is not immediately after the fread that reads data_len."


def test_parser_runs_past_255_records_and_extracts_deleted_file(parser_exe, tmp_path):
    record_count = 270 + secrets.randbelow(80)
    recovered_name = f"deleted_{secrets.token_hex(8)}.bin"
    recovered_data = secrets.token_bytes(73)
    records = []

    for i in range(record_count - 1):
        name = f"active_{i}_{secrets.token_hex(3)}.dat".encode()
        data = secrets.token_bytes(5 + secrets.randbelow(20))
        records.append(struct.pack(f"<BB{len(name)}sH{len(data)}s", 1, len(name), name, len(data), data))

    name = recovered_name.encode()
    records.append(struct.pack(
        f"<BB{len(name)}sH{len(recovered_data)}s",
        0, len(name), name, len(recovered_data), recovered_data,
    ))

    dump = tmp_path / "fs_dump.bin"
    with open(dump, "wb") as f:
        f.write(b"DUMP")
        f.write(struct.pack("<H", record_count))
        for record in records:
            f.write(record)

    result = subprocess.run(
        [str(parser_exe)], cwd=tmp_path,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8,
    )
    assert result.returncode == 0, f"Parser failed on a valid dump: {result.stderr.decode(errors='replace')}"
    extracted = tmp_path / recovered_name
    assert extracted.is_file(), "Parser did not extract the deleted record after record 255."
    assert extracted.read_bytes() == recovered_data, "Extracted file contents are incorrect."


def test_parser_extracts_sql_from_supplied_dump(parser_exe, tmp_path):
    assert os.path.isfile(FS_DUMP), f"{FS_DUMP} is missing."
    target_dump = tmp_path / "fs_dump.bin"
    target_dump.write_bytes(open(FS_DUMP, "rb").read())
    result = subprocess.run(
        [str(parser_exe)], cwd=tmp_path,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8,
    )
    assert result.returncode == 0, f"Parser failed on the supplied fs_dump.bin: {result.stderr.decode(errors='replace')}"
    extracted = tmp_path / "recovered_query.sql"
    assert extracted.is_file(), "Parser did not recover recovered_query.sql from the supplied dump."
    assert extracted.read_bytes() == ORIGINAL_SQL, "Parser did not recover the SQL file faithfully."


def test_oversized_data_len_triggers_assertion(parser_exe, tmp_path):
    name = b"oversized.bin"
    with open(tmp_path / "fs_dump.bin", "wb") as f:
        f.write(b"DUMP")
        f.write(struct.pack("<H", 1))
        f.write(struct.pack(f"<BB{len(name)}sH", 1, len(name), name, 10000))

    result = subprocess.run(
        [str(parser_exe)], cwd=tmp_path,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5,
    )
    assert result.returncode == -signal.SIGABRT, \
        "A record with data_len == 10000 did not trigger the required assertion."


def load_corrected_sql():
    assert os.path.isfile(RECOVERED_SQL), f"{RECOVERED_SQL} is missing."
    with open(RECOVERED_SQL, "r", encoding="utf-8") as f:
        sql = f.read().strip()
    assert sql, "recovered_query.sql is empty."
    lower = sql.lower()
    assert "is_deleted" in lower and "1" in lower, \
        "The recovered_query.sql does not seem to contain the filter for is_deleted = 1."
    return sql


def test_corrected_sql_semantics_on_independent_data():
    sql = load_corrected_sql()
    token = secrets.token_hex(6)
    expected = {f"deleted_admin_a_{token}", f"deleted_admin_b_{token}"}
    rows = [
        (101, f"active_admin_{token}", "admin", 0),
        (207, f"deleted_admin_a_{token}", "admin", 1),
        (319, f"deleted_user_{token}", "user", 1),
        (421, f"active_user_{token}", "user", 0),
        (533, f"deleted_admin_b_{token}", "admin", 1),
    ]
    conn = sqlite3.connect(":memory:")
    try:
        conn.execute("CREATE TABLE employees (id INTEGER PRIMARY KEY, username TEXT, role TEXT, is_deleted INTEGER)")
        conn.executemany("INSERT INTO employees VALUES (?, ?, ?, ?)", rows)
        result = conn.execute(sql).fetchall()
    finally:
        conn.close()
    assert all(len(row) == 1 for row in result), "The corrected query must output only the username column."
    assert {row[0] for row in result} == expected and len(result) == len(expected), \
        "The corrected query does not exclusively return deleted administrators."


def test_final_result_exists_and_correct():
    assert os.path.isfile(FINAL_RESULT), f"{FINAL_RESULT} is missing."
    assert os.path.isfile(COMPANY_DB), f"{COMPANY_DB} is missing."

    conn = sqlite3.connect(f"file:{COMPANY_DB}?mode=ro", uri=True)
    try:
        expected_rows = [row[0] for row in conn.execute(
            "SELECT username FROM employees WHERE role = 'admin' AND is_deleted = 1;"
        ).fetchall()]
        submitted_rows = conn.execute(load_corrected_sql()).fetchall()
    finally:
        conn.close()

    assert all(len(row) == 1 for row in submitted_rows), \
        "The corrected SQL must produce one raw username column."
    assert {row[0] for row in submitted_rows} == set(expected_rows) and len(submitted_rows) == len(expected_rows), \
        "The corrected SQL does not produce the required rows on company.db."

    with open(FINAL_RESULT, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert set(actual_lines) == set(expected_rows), \
        f"The contents of {FINAL_RESULT} do not match the expected query results. " \
        f"Expected: {expected_rows}, but got: {actual_lines}"


def test_recovered_sql_contains_is_deleted_filter():
    # Preserve the original content assertion while making the SQL artifact mandatory.
    content = load_corrected_sql().lower()
    assert "is_deleted" in content and "1" in content, \
        "The recovered_query.sql does not seem to contain the filter for is_deleted = 1."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
