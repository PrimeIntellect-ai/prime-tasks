#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import sqlite3
import string
import subprocess
import tempfile
from pathlib import Path

WORKSPACE_DIR = "/home/user/workspace"
CLEAN_DATA_CSV = os.path.join(WORKSPACE_DIR, "clean_data.csv")
DB_PATH = os.path.join(WORKSPACE_DIR, "patients.db")

EXPECTED_DB_ROWS = [
    (101, "AS", "[REDACTED]", 1, 120),
    (101, "AS", "[REDACTED]", 2, 118),
    (102, "BJ", "[REDACTED]", 1, 130),
    (102, "BJ", "[REDACTED]", 3, 140),
    (104, "DP", "[REDACTED]", 1, 115),
    (104, "DP", "[REDACTED]", 2, 116),
    (104, "DP", "[REDACTED]", 3, 117),
]

EXPECTED_CSV_LINES = [
    "ID,Initials,Email,Month,BP",
    "101,AS,[REDACTED],1,120",
    "101,AS,[REDACTED],2,118",
    "102,BJ,[REDACTED],1,130",
    "102,BJ,[REDACTED],3,140",
    "104,DP,[REDACTED],1,115",
    "104,DP,[REDACTED],2,116",
    "104,DP,[REDACTED],3,117",
]

def test_clean_data_csv_exists_and_content():
    assert os.path.isfile(CLEAN_DATA_CSV), f"File {CLEAN_DATA_CSV} does not exist."

    with open(CLEAN_DATA_CSV, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == EXPECTED_CSV_LINES, f"Content of {CLEAN_DATA_CSV} does not match the expected output."

def test_database_exists_and_content():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='bp_log';")
    assert cursor.fetchone() is not None, "Table 'bp_log' does not exist in the database."

    cursor.execute("SELECT ID, Initials, Email, Month, BP FROM bp_log ORDER BY ID, Month;")
    rows = cursor.fetchall()

    assert rows == EXPECTED_DB_ROWS, f"Database rows in 'bp_log' do not match expected output."

    conn.close()

def test_makefile_exists():
    makefile_path = os.path.join(WORKSPACE_DIR, "Makefile")
    assert os.path.isfile(makefile_path), "Makefile is missing."

def test_c_program_exists():
    c_prog_path = os.path.join(WORKSPACE_DIR, "cleaner.c")
    assert os.path.isfile(c_prog_path), "cleaner.c is missing."

def test_executable_exists():
    exe_path = os.path.join(WORKSPACE_DIR, "cleaner")
    assert os.path.isfile(exe_path) and os.access(exe_path, os.X_OK), "Executable 'cleaner' is missing or not executable."


def random_word():
    return secrets.choice(string.ascii_uppercase) + "".join(
        secrets.choice(string.ascii_lowercase) for _ in range(7)
    )


def make_fixture():
    base = secrets.randbelow(700000) + 200000
    first1, last1 = random_word(), random_word()
    first2 = random_word()
    first3, last3 = random_word(), random_word()
    p1 = secrets.randbelow(80) + 80
    p2 = secrets.randbelow(80) + 80
    p3 = secrets.randbelow(80) + 80
    p4 = secrets.randbelow(80) + 80
    p5 = secrets.randbelow(80) + 80
    p6 = secrets.randbelow(80) + 80

    input_rows = [
        [str(base), f"{first1} {last1}", f"{first1.lower()}@hidden.test", str(p1), "0", "-7"],
        [str(base + 1), first2, f"{first2.lower()}@hidden.test", "", str(p2), str(p3)],
        [str(base + 2), f"{first3} {last3}", f"{first3.lower()}@hidden.test", str(p4), str(p5), str(p6)],
    ]
    expected = [
        (base, first1[0] + last1[0], "[REDACTED]", 1, p1),
        (base + 1, first2[0], "[REDACTED]", 2, p2),
        (base + 1, first2[0], "[REDACTED]", 3, p3),
        (base + 2, first3[0] + last3[0], "[REDACTED]", 1, p4),
        (base + 2, first3[0] + last3[0], "[REDACTED]", 2, p5),
        (base + 2, first3[0] + last3[0], "[REDACTED]", 3, p6),
    ]
    return input_rows, expected


def write_fixture(path, rows):
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["ID", "FullName", "Email", "M1_BP", "M2_BP", "M3_BP"])
        writer.writerows(rows)


def read_clean_csv(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        return list(csv.reader(f))


def expected_csv_rows(expected):
    return [["ID", "Initials", "Email", "Month", "BP"]] + [
        [str(row[0]), row[1], row[2], str(row[3]), str(row[4])] for row in expected
    ]


def test_z_source_and_make_pipeline_on_unseen_fixture():
    workspace = Path(WORKSPACE_DIR)
    source = workspace / "cleaner.c"
    makefile = workspace / "Makefile"
    schema = workspace / "schema.sql"
    assert source.is_file(), "cleaner.c is missing."
    assert makefile.is_file(), "Makefile is missing."
    assert schema.is_file(), "schema.sql is missing."

    rows, expected = make_fixture()

    # Compile cleaner.c independently and execute that compiled artifact on an
    # unseen input, so dummy source or a hardcoded executable cannot pass.
    with tempfile.TemporaryDirectory() as td:
        hidden_input = Path(td) / "input.csv"
        hidden_output = Path(td) / "output.csv"
        compiled = Path(td) / "cleaner_from_source"
        write_fixture(hidden_input, rows)
        subprocess.run(
            ["gcc", str(source), "-o", str(compiled)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compiled.is_file() and os.access(compiled, os.X_OK)
        subprocess.run(
            [str(compiled), str(hidden_input), str(hidden_output)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert hidden_output.is_file(), "Compiled cleaner did not create its requested output."
        assert read_clean_csv(hidden_output) == expected_csv_rows(expected)

    # Exercise the submitted orchestration from a clean state on the same
    # unpredictable fixture and derive all expected results in the verifier.
    clinical = workspace / "clinical_data.csv"
    original_clinical = clinical.read_bytes()
    try:
        write_fixture(clinical, rows)
        for artifact in (workspace / "cleaner", workspace / "clean_data.csv", workspace / "patients.db"):
            artifact.unlink(missing_ok=True)

        subprocess.run(
            ["make", "all"],
            cwd=workspace,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )

        built_cleaner = workspace / "cleaner"
        clean_csv = workspace / "clean_data.csv"
        database = workspace / "patients.db"
        assert built_cleaner.is_file() and os.access(built_cleaner, os.X_OK)
        assert clean_csv.is_file()
        assert read_clean_csv(clean_csv) == expected_csv_rows(expected)
        assert database.is_file() and database.stat().st_size > 0

        with sqlite3.connect(database) as conn:
            table = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='bp_log'"
            ).fetchone()
            assert table is not None, "Table 'bp_log' was not created."
            columns = conn.execute("PRAGMA table_info(bp_log)").fetchall()
            assert [(c[1], c[2].upper()) for c in columns] == [
                ("ID", "INTEGER"),
                ("Initials", "TEXT"),
                ("Email", "TEXT"),
                ("Month", "INTEGER"),
                ("BP", "INTEGER"),
            ]
            actual = conn.execute(
                "SELECT ID, Initials, Email, Month, BP FROM bp_log ORDER BY ID, Month"
            ).fetchall()
            assert actual == expected
    finally:
        clinical.write_bytes(original_clinical)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
