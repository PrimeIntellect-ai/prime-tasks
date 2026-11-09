#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import shutil
import sqlite3
import subprocess

import pytest

CSV_PATH = "/home/user/report.csv"
GO_PATH = "/home/user/generate_report.go"
DB_PATH = "/home/user/backups.db"
BINARY_PATH = "/tmp/generate_report_submission"

EXPECTED_LINES = [
    "job_name,suite_id,size_bytes,size_rank",
    "full_cluster_backup,100,5000,1",
    "db_primary,100,2000,2",
    "db_replica,100,2000,2",
    "user_uploads,101,15000,1",
    "app_logs,101,8000,2",
    "cache_dump,102,1000,1",
]


def read_nonempty_lines(path):
    with open(path, "r", newline="") as f:
        return [line.strip() for line in f if line.strip()]


def run_program():
    if os.path.lexists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(
        [BINARY_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"generate_report program failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(CSV_PATH), f"File {CSV_PATH} does not exist after running the program."
    assert os.path.isfile(CSV_PATH), f"{CSV_PATH} is not a regular file after running the program."


def expected_report_from_database():
    con = sqlite3.connect(DB_PATH)
    try:
        jobs = {
            row[0]: (row[1], row[2], row[3])
            for row in con.execute("SELECT id, name, suite_id, size_bytes FROM backup_jobs")
        }
        children = {}
        for job_id, parent_id in con.execute(
            "SELECT job_id, parent_job_id FROM job_dependencies"
        ):
            children.setdefault(parent_id, []).append(job_id)

        selected = {job_id for job_id, job in jobs.items() if job[0] == "full_cluster_backup"}
        pending = list(selected)
        while pending:
            parent = pending.pop()
            for child in children.get(parent, []):
                if child not in selected:
                    selected.add(child)
                    pending.append(child)

        rows = []
        for job_id in selected:
            name, suite_id, size_bytes = jobs[job_id]
            suite_sizes = [jobs[other][2] for other in selected if jobs[other][1] == suite_id]
            size_rank = 1 + sum(1 for size in suite_sizes if size > size_bytes)
            rows.append([name, str(suite_id), str(size_bytes), str(size_rank)])

        rows.sort(key=lambda row: (int(row[1]), int(row[3]), row[0]))
        return [["job_name", "suite_id", "size_bytes", "size_rank"]] + rows
    finally:
        con.close()


def test_report_csv_exists_and_correct():
    assert os.path.exists(CSV_PATH), f"File {CSV_PATH} does not exist."
    assert os.path.isfile(CSV_PATH), f"{CSV_PATH} is not a regular file."
    assert read_nonempty_lines(CSV_PATH) == EXPECTED_LINES, (
        f"Content of {CSV_PATH} does not match expected output."
    )


def test_go_file_exists():
    assert os.path.exists(GO_PATH), f"File {GO_PATH} does not exist."
    assert os.path.isfile(GO_PATH), f"{GO_PATH} is not a regular file."


def test_program_uses_required_sql_and_generates_report_dynamically():
    with open(GO_PATH, "r", encoding="utf-8") as f:
        source = f.read()

    # Ignore ordinary Go comments when looking for the required SQL constructs.
    uncommented = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    uncommented = re.sub(r"(?m)^\s*//.*$", " ", uncommented)
    assert re.search(r"\bWITH\s+RECURSIVE\b", uncommented, flags=re.I), (
        "generate_report.go does not contain a recursive CTE."
    )
    assert re.search(r"\bRANK\s*\(\s*\)\s*OVER\s*\(", uncommented, flags=re.I), (
        "generate_report.go does not contain the required RANK window function."
    )

    build = subprocess.run(
        ["go", "build", "-o", BINARY_PATH, GO_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert build.returncode == 0, (
        f"generate_report.go did not compile.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )

    # Execute against the original database and retain the original exact check.
    run_program()
    assert read_nonempty_lines(CSV_PATH) == EXPECTED_LINES, (
        "Running generate_report.go against the original database did not produce the expected report."
    )

    backup_path = "/tmp/backups.db.verifier_backup"
    shutil.copy2(DB_PATH, backup_path)
    try:
        con = sqlite3.connect(DB_PATH)
        try:
            con.executescript("""
                UPDATE backup_jobs SET size_bytes = 7000 WHERE id = 1;
                UPDATE backup_jobs SET size_bytes = 8000 WHERE id = 2;
                UPDATE backup_jobs SET size_bytes = 7000 WHERE id = 3;
                UPDATE backup_jobs SET size_bytes = 3000 WHERE id = 4;
                UPDATE backup_jobs SET size_bytes = 12000 WHERE id = 5;

                INSERT INTO backup_jobs VALUES (8, 'late_archive', 100, 9000);
                INSERT INTO backup_jobs VALUES (9, 'deep_manifest', 101, 3000);
                INSERT INTO backup_jobs VALUES (10, 'dynamic_suite_job', 103, 4444);
                INSERT INTO backup_jobs VALUES (11, 'large_unrelated', 100, 999999);

                INSERT INTO job_dependencies VALUES (8, 5);
                INSERT INTO job_dependencies VALUES (9, 8);
                INSERT INTO job_dependencies VALUES (10, 9);
            """)
            con.commit()
        finally:
            con.close()

        expected = expected_report_from_database()
        run_program()
        with open(CSV_PATH, "r", newline="") as f:
            actual = list(csv.reader(f))
        assert actual == expected, (
            "The program did not dynamically query the modified database, recursively include new "
            "descendants, rank within suites, and sort the resulting rows correctly.\n"
            f"Expected: {expected}\nActual: {actual}"
        )
    finally:
        shutil.copy2(backup_path, DB_PATH)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
