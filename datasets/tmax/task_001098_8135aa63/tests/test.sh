#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import sqlite3
import subprocess

PIPELINE_DIR = "/home/user/pipeline"
BUILD_SH = os.path.join(PIPELINE_DIR, "build.sh")
PARSER_PY = os.path.join(PIPELINE_DIR, "parser.py")
DATA_CSV = os.path.join(PIPELINE_DIR, "data.csv")
DATA_LOG = os.path.join(PIPELINE_DIR, "data.log")
REPORT_TXT = os.path.join(PIPELINE_DIR, "report.txt")
DB_FILE = os.path.join(PIPELINE_DIR, "db.sqlite")

CANONICAL_CSV = """id,username,status
1,alice,active
2,bob,inactive
3,charlie,active
4,dave,active
"""
CANONICAL_LOG = """INFO|alice|Login successful
INFO|bob|Login failed
ERROR|charlie|Database error|Timeout occurred
INFO|alice|Logout
"""


def write_canonical_fixture():
    with open(DATA_CSV, "w", newline="") as f:
        f.write(CANONICAL_CSV)
    with open(DATA_LOG, "w", newline="") as f:
        f.write(CANONICAL_LOG)


def run_build():
    if os.path.exists(REPORT_TXT):
        os.remove(REPORT_TXT)
    result = subprocess.run(
        [BUILD_SH],
        cwd=PIPELINE_DIR,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"build.sh failed with return code {result.returncode}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def read_report():
    assert os.path.isfile(REPORT_TXT), f"File {REPORT_TXT} was not generated."
    with open(REPORT_TXT, "r") as f:
        return f.read()


def derive_expected(csv_path, log_path):
    with open(csv_path, newline="") as f:
        active = {
            row["username"]
            for row in csv.DictReader(f)
            if row["status"] == "active"
        }

    seen = set()
    with open(log_path) as f:
        for line in f:
            if not line.strip():
                continue
            parts = line.strip().split("|", 2)
            assert len(parts) == 3
            seen.add(parts[1])

    users = sorted(active & seen)
    return f"Active users seen in logs: {','.join(users)}\n"


def test_build_sh_executes_cleanly():
    assert os.path.isfile(BUILD_SH), f"Script {BUILD_SH} is missing."
    assert os.access(BUILD_SH, os.X_OK), f"Script {BUILD_SH} is not executable."
    assert os.path.isfile(PARSER_PY), f"Parser {PARSER_PY} is missing."
    write_canonical_fixture()
    run_build()


def test_report_txt_content():
    content = read_report()
    expected = "Active users seen in logs: alice,charlie\n"
    assert content == expected, f"Expected report content {expected!r}, but got {content!r}"


def test_pipeline_on_unseen_data_and_edge_case_log_message():
    suffix = secrets.token_hex(6)
    active_seen = f"active_seen_{suffix}"
    active_pipe = f"active_pipe_{suffix}"
    inactive_seen = f"inactive_seen_{suffix}"
    active_absent = f"active_absent_{suffix}"
    unknown = f"unknown_{suffix}"

    rows = [
        (17, active_seen, "active"),
        (31, inactive_seen, "inactive"),
        (46, active_absent, "active"),
        (92, active_pipe, "active"),
    ]
    with open(DATA_CSV, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "username", "status"])
        writer.writerows(rows)

    with open(DATA_LOG, "w", newline="") as f:
        f.write(f"INFO|{inactive_seen}|Login attempt\n")
        f.write(f"ERROR|{active_pipe}|Failure detail|nested|pipe content\n")
        f.write("\n")
        f.write(f"INFO|{active_seen}|Login successful\n")
        f.write(f"WARN|{unknown}|Not present in database\n")
        f.write(f"INFO|{active_seen}|Duplicate event\n")

    expected_report = derive_expected(DATA_CSV, DATA_LOG)
    run_build()
    assert read_report() == expected_report

    assert os.path.isfile(DB_FILE), "build.sh did not create db.sqlite"
    with sqlite3.connect(DB_FILE) as conn:
        imported = conn.execute(
            "SELECT id, username, status FROM users ORDER BY id"
        ).fetchall()
    assert imported == rows, (
        "The CSV was not imported into the users table correctly; "
        f"expected {rows!r}, got {imported!r}"
    )

    # Exercise parser.py itself against the database produced by build.sh. This
    # prevents build.sh from passing by writing a canned report without fixing
    # the parser's edge-case parsing and database query.
    os.remove(REPORT_TXT)
    result = subprocess.run(
        ["python3", PARSER_PY],
        cwd=PIPELINE_DIR,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"parser.py failed with return code {result.returncode}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    assert read_report() == expected_report
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
