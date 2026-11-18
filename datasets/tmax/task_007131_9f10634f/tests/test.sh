#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import csv
import json
import os
import shutil
import sqlite3
import stat
import subprocess
import tempfile
import uuid


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, timeout=15, **kwargs)


def test_processor_c_exists():
    path = "/home/user/processor.c"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "#include" in content, f"{path} does not look like valid C code."


def test_processor_executable_exists():
    path = "/home/user/processor"
    assert os.path.isfile(path), f"Compiled executable {path} is missing."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled executable."


def test_run_pipeline_sh_exists_and_executable():
    path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(path), f"Script {path} is missing."
    assert os.access(path, os.X_OK), f"Script {path} is not executable."
    with open(path, "r") as f:
        content = f.read()
    assert "sqlite3" in content, "Pipeline does not invoke sqlite3."
    assert "processor" in content, "Pipeline does not invoke the processor."
    assert "backup_report.txt" in content, "Pipeline does not create backup_report.txt."
    assert "|" in content, "Pipeline does not pipe the CSV output into the processor."
    assert ">" in content, "Pipeline does not redirect output to the report."


def test_backup_report_txt_content():
    path = "/home/user/backup_report.txt"
    assert os.path.isfile(path), f"Report file {path} is missing."
    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_lines = [
        "[2023-10-01] users_db::profiles",
        "[2023-10-02] orders_db::transactions",
        "[2023-10-03] users_db::profiles",
    ]
    assert sorted(lines) == sorted(expected_lines), f"Content of {path} does not match the expected output."


def test_processor_source_and_binary_process_runtime_input():
    token = uuid.uuid4().hex
    rows = [
        ["db_" + token, "table_a_" + token, "2098-01-17"],
        ["db_b_" + token, "table_b_" + token, "2098-02-23"],
    ]
    csv_input = "".join(",".join(row) + "\n" for row in rows)
    expected = "".join(f"[{row[2]}] {row[0]}::{row[1]}\n" for row in rows)

    supplied = run(["/home/user/processor"], input=csv_input)
    assert supplied.stdout == expected, "The compiled processor does not transform CSV input correctly."

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "processor")
        run(["gcc", "-std=c11", "-O2", "/home/user/processor.c", "-o", rebuilt])
        rebuilt_result = run([rebuilt], input=csv_input)
        assert rebuilt_result.stdout == expected, "processor.c does not compile to a working processor."


def test_pipeline_executes_correct_join_filter_and_processor():
    home = "/home/user"
    db_path = os.path.join(home, "backup_meta.db")
    processor_path = os.path.join(home, "processor")
    report_path = os.path.join(home, "backup_report.txt")
    pipeline_path = os.path.join(home, "run_pipeline.sh")

    token = uuid.uuid4().hex
    db_backup = tempfile.mktemp(prefix="backup_meta_", suffix=".db")
    processor_backup = tempfile.mktemp(prefix="processor_")
    report_backup = tempfile.mktemp(prefix="report_")
    report_existed = os.path.exists(report_path)
    shutil.copy2(db_path, db_backup)
    shutil.copy2(processor_path, processor_backup)
    if report_existed:
        shutil.copy2(report_path, report_backup)

    try:
        con = sqlite3.connect(db_path)
        try:
            next_db = con.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM databases").fetchone()[0]
            next_table = con.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM tables").fetchone()[0]
            next_backup = con.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM backups").fetchone()[0]

            db_name = "verify_db_" + token
            table_name = "verify_table_" + token
            ignored_table = "ignored_table_" + token
            con.execute("INSERT INTO databases(id, name) VALUES (?, ?)", (next_db, db_name))
            con.execute("INSERT INTO tables(id, db_id, name, row_count) VALUES (?, ?, ?, ?)",
                        (next_table, next_db, table_name, 17))
            con.execute("INSERT INTO tables(id, db_id, name, row_count) VALUES (?, ?, ?, ?)",
                        (next_table + 1, next_db, ignored_table, 18))
            con.executemany(
                "INSERT INTO backups(id, table_id, backup_date, status) VALUES (?, ?, ?, ?)",
                [
                    (next_backup, next_table, "2099-04-11", "SUCCESS"),
                    (next_backup + 1, next_table, "2099-04-12", "FAILED"),
                    (next_backup + 2, next_table + 1, "2099-04-13", "success"),
                    (next_backup + 3, next_table + 1, "2099-04-14", "SUCCESS "),
                    (next_backup + 4, next_table + 50000, "2099-04-15", "SUCCESS"),
                ],
            )
            con.commit()

            expected_rows = con.execute(
                "SELECT d.name, t.name, b.backup_date "
                "FROM databases AS d "
                "JOIN tables AS t ON t.db_id = d.id "
                "JOIN backups AS b ON b.table_id = t.id "
                "WHERE b.status = 'SUCCESS'"
            ).fetchall()
        finally:
            con.close()

        expected_lines = [f"[{date}] {db}::{table}" for db, table, date in expected_rows]

        run([pipeline_path], cwd=home)
        assert os.path.isfile(report_path), "The pipeline did not create backup_report.txt."
        with open(report_path, "r") as f:
            actual_lines = [line.rstrip("\n") for line in f if line.rstrip("\n")]
        assert collections.Counter(actual_lines) == collections.Counter(expected_lines), (
            "Running the pipeline did not produce the correctly joined, SUCCESS-only report."
        )

        sentinel = "/tmp/processor_called_" + token
        os.unlink(processor_path)
        wrapper = '''#!/usr/bin/env python3
import collections
import csv
import json
import os
import sys
rows = list(csv.reader(sys.stdin))
expected = json.loads(os.environ["VERIFIER_EXPECTED_ROWS"])
if collections.Counter(map(tuple, rows)) != collections.Counter(map(tuple, expected)):
    sys.exit(41)
with open(os.environ["VERIFIER_SENTINEL"], "w") as f:
    f.write("called")
for db, table, date in rows:
    print(f"[{date}] {db}::{table}")
'''
        with open(processor_path, "w") as f:
            f.write(wrapper)
        os.chmod(processor_path, 0o755)

        env = os.environ.copy()
        env["VERIFIER_EXPECTED_ROWS"] = json.dumps([list(row) for row in expected_rows])
        env["VERIFIER_SENTINEL"] = sentinel
        run([pipeline_path], cwd=home, env=env)
        assert os.path.isfile(sentinel), "run_pipeline.sh did not pipe its CSV into /home/user/processor."

        with open(report_path, "r") as f:
            wrapped_lines = [line.rstrip("\n") for line in f if line.rstrip("\n")]
        assert collections.Counter(wrapped_lines) == collections.Counter(expected_lines)
    finally:
        shutil.copy2(db_backup, db_path)
        if os.path.lexists(processor_path):
            os.unlink(processor_path)
        shutil.copy2(processor_backup, processor_path)
        if report_existed:
            shutil.copy2(report_backup, report_path)
        elif os.path.exists(report_path):
            os.unlink(report_path)
        for path in (db_backup, processor_backup, report_backup):
            if os.path.exists(path):
                os.unlink(path)
        sentinel_path = "/tmp/processor_called_" + token
        if os.path.exists(sentinel_path):
            os.unlink(sentinel_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
