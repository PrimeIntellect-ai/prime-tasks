#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

APP = "/home/user/app"
RAW_LOGS = os.path.join(APP, "raw_logs.txt")
DB_PATH = os.path.join(APP, "db.sqlite")
PARSER_SOURCE = os.path.join(APP, "parser.c")
PARSER_BINARY = os.path.join(APP, "parser")
ANALYZER = os.path.join(APP, "analyzer.py")
REPORT = "/home/user/forensics_report.txt"

EXPECTED_RAW = """10.0.1.15|2023-10-25T08:12:01Z|200|/index.html
10.0.1.22|2023-10-25T08:12:05Z|500|/api/checkout
10.0.1.33|2023-10-25T08:12:10Z|200|/images/logo.png
10.0.1.99|2023-10-25T08:12:15Z|200
10.0.1.45|2023-10-25T08:12:20Z|500|/api/login
10.0.1.50|2023-10-25T08:12:25Z|404|/favicon.ico
"""

EXPECTED_ROWS = [
    ("10.0.1.15", "2023-10-25T08:12:01Z", "200", "/index.html"),
    ("10.0.1.22", "2023-10-25T08:12:05Z", "500", "/api/checkout"),
    ("10.0.1.33", "2023-10-25T08:12:10Z", "200", "/images/logo.png"),
    ("10.0.1.45", "2023-10-25T08:12:20Z", "500", "/api/login"),
    ("10.0.1.50", "2023-10-25T08:12:25Z", "404", "/favicon.ico"),
]


def read_rows(db_path):
    conn = sqlite3.connect(db_path)
    try:
        return conn.execute(
            "SELECT ip, timestamp, status, path FROM logs ORDER BY rowid"
        ).fetchall()
    finally:
        conn.close()


def exercise_parser(binary):
    token = uuid.uuid4().hex
    valid_rows = [
        (f"172.19.0.{int(token[0], 16) + 1}", f"time-{token[:8]}", "500", f"/first/{token[8:16]}"),
        (f"172.20.0.{int(token[1], 16) + 1}", f"time-{token[16:24]}", "201", f"/second/{token[24:]}"),
        (f"172.21.0.{int(token[2], 16) + 1}", f"time-{token[4:12]}", "500", f"/third/{token[12:20]}"),
    ]
    lines = [
        "|".join(valid_rows[0]),
        f"broken-{token}",
        f"192.0.2.1|time-{token}|500",
        f"192.0.2.2|time-{token}",
        "|".join(valid_rows[1]),
        "|".join(valid_rows[2]),
    ]

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "unseen_logs.txt")
        output_db = os.path.join(td, "output.sqlite")
        with open(input_path, "w") as f:
            f.write("\n".join(lines) + "\n")

        result = subprocess.run(
            [binary, input_path, output_db],
            cwd=APP,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Parser failed on malformed input (exit {result.returncode}). "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert os.path.isfile(output_db), "Parser did not create its requested database."
        assert read_rows(output_db) == valid_rows, (
            "Parser did not insert all valid records while skipping every malformed record."
        )


def test_raw_logs_unmodified():
    assert os.path.isfile(RAW_LOGS), f"File {RAW_LOGS} is missing."
    with open(RAW_LOGS, "r") as f:
        content = f.read()
    assert content == EXPECTED_RAW, "raw_logs.txt was modified, which violates the constraints."


def test_parser_source_build_and_behavior():
    assert os.path.isfile(PARSER_SOURCE), f"Source file {PARSER_SOURCE} is missing."

    build = subprocess.run(
        ["make", "-B", "parser"],
        cwd=APP,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert build.returncode == 0, f"make failed: {build.stdout}\n{build.stderr}"
    assert os.path.isfile(PARSER_BINARY) and os.access(PARSER_BINARY, os.X_OK), (
        "make did not produce an executable parser."
    )
    with open(PARSER_BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The rebuilt parser is not a compiled ELF executable."
    exercise_parser(PARSER_BINARY)

    # Compile parser.c independently as well, so a replacement Makefile cannot hide
    # an unfixed source file behind a fabricated parser executable.
    with tempfile.TemporaryDirectory() as td:
        source_binary = os.path.join(td, "parser-from-source")
        compile_result = subprocess.run(
            ["gcc", "-g", "-O0", PARSER_SOURCE, "-o", source_binary, "-lsqlite3"],
            cwd=APP,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            f"parser.c does not compile: {compile_result.stdout}\n{compile_result.stderr}"
        )
        exercise_parser(source_binary)


def test_database_populated():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing. Did you run the parser?"
    try:
        rows = read_rows(DB_PATH)
    except sqlite3.Error as e:
        assert False, f"Failed to query the logs table: {e}"

    assert len(rows) == 5, (
        f"Expected 5 rows in the logs table, but found {len(rows)}. "
        "Did you skip the malformed line correctly?"
    )
    assert rows == EXPECTED_ROWS, "The database does not contain the records produced from raw_logs.txt."


def test_forensics_report():
    assert os.path.isfile(REPORT), f"Forensics report {REPORT} is missing."
    with open(REPORT, "r") as f:
        lines = [line.strip() for line in f.read().strip().split("\n")]

    assert len(lines) == 3, f"Forensics report should have exactly 3 lines, but found {len(lines)}."
    assert lines[0] == "10.0.1.99|2023-10-25T08:12:15Z|200", (
        f"Line 1 of report is incorrect. Found: {lines[0]}"
    )
    assert lines[1] == "5", f"Line 2 of report is incorrect. Expected '5', found: {lines[1]}"
    assert lines[2] == "10.0.1.22,10.0.1.45", f"Line 3 of report is incorrect. Found: {lines[2]}"


def test_analyzer_script_fixed():
    assert os.path.isfile(ANALYZER), f"Script {ANALYZER} is missing."
    with open(ANALYZER, "r") as f:
        content = f.read()

    assert "status = '500'" in content or 'status="500"' in content or "status=500" in content or "status = 500" in content, (
        "analyzer.py does not appear to query for status 500."
    )

    expected = ",".join(row[0] for row in EXPECTED_ROWS if row[2] == "500")
    result = subprocess.run(
        ["python3", ANALYZER],
        cwd=APP,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, f"analyzer.py failed: {result.stderr}"
    assert result.stdout.strip() == expected, "analyzer.py does not report the 500-status IPs from db.sqlite."


def test_analyzer_against_unseen_database():
    token = uuid.uuid4().hex
    records = [
        (f"198.51.100.{int(token[0], 16) + 1}", "t1", "404", "/ignore"),
        (f"203.0.113.{int(token[1], 16) + 20}", "t2", "500", f"/a/{token[:8]}"),
        (f"192.0.2.{int(token[2], 16) + 40}", "t3", "200", "/ignore2"),
        (f"203.0.113.{int(token[3], 16) + 60}", "t4", "500", f"/b/{token[8:16]}"),
    ]
    expected = ",".join(row[0] for row in records if row[2] == "500")

    with tempfile.TemporaryDirectory() as td:
        backup = os.path.join(td, "original.sqlite")
        shutil.copy2(DB_PATH, backup)
        try:
            os.remove(DB_PATH)
            conn = sqlite3.connect(DB_PATH)
            conn.execute("CREATE TABLE logs (ip TEXT, timestamp TEXT, status TEXT, path TEXT)")
            conn.executemany("INSERT INTO logs VALUES (?, ?, ?, ?)", records)
            conn.commit()
            conn.close()

            result = subprocess.run(
                ["python3", ANALYZER],
                cwd=APP,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=15,
            )
            assert result.returncode == 0, f"analyzer.py failed on a valid database: {result.stderr}"
            assert result.stdout.strip() == expected, (
                "analyzer.py did not derive the HTTP 500 IP addresses from an unseen database."
            )
        finally:
            if os.path.exists(DB_PATH):
                os.remove(DB_PATH)
            shutil.copy2(backup, DB_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
