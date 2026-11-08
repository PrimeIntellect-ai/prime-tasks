#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import re
import secrets
import sqlite3
import subprocess
import pytest

SCRIPT_PATH = "/home/user/process_customers.sh"
DB_PATH = "/home/user/customers.db"
CSV_PATH = "/home/user/recent_customers.csv"
RAW_DIR = "/home/user/raw_data"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_database_exists_and_valid():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} does not exist."

    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("PRAGMA integrity_check;")
        result = cursor.fetchone()
        assert result[0] == "ok", "Database integrity check failed."
    except sqlite3.Error as e:
        pytest.fail(f"Failed to open or query SQLite database: {e}")
    finally:
        if 'conn' in locals():
            conn.close()


def test_database_count():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} does not exist."

    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT count(*) FROM customers;")
        count = cursor.fetchone()[0]
        assert count == 7, f"Expected 7 records in the customers table, found {count}."
    except sqlite3.Error as e:
        pytest.fail(f"Failed to query customers table: {e}")
    finally:
        if 'conn' in locals():
            conn.close()


def test_recent_customers_csv():
    assert os.path.isfile(CSV_PATH), f"File {CSV_PATH} does not exist."

    expected_content = (
        "2,Bob Jones,5553334444,2020-01-15\n"
        "3,Renée Dupont,15559990000,2021-05-20\n"
        "5,Dave Brown,5556667777,2020-03-10\n"
        "6,Eve White,5557778888,2022-08-22"
    )

    with open(CSV_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content == expected_content, (
        f"Content of {CSV_PATH} does not match the expected result.\n"
        f"Expected:\n{expected_content}\n\nGot:\n{content}"
    )


def test_script_executes_complete_pipeline_on_fresh_inputs():
    base = 1000 + secrets.randbelow(7000)
    ids = [base + n for n in (31, 4, 67, 12, 53, 25, 46)]
    digits = ''.join(str(secrets.randbelow(10)) for _ in range(70))
    phones = [digits[i:i + 10] for i in range(0, 70, 10)]

    source_rows = [
        (ids[0], "mARIA loPEZ", f"({phones[0][:3]}) {phones[0][3:6]}-{phones[0][6:]}", "06/14/2017"),
        (ids[1], "andré MARTIN", f"{phones[1][:3]}.{phones[1][3:6]}.{phones[1][6:]}", "09/03/2020"),
        (ids[2], "zoe KING", f"+1 {phones[2][:3]} {phones[2][3:6]} {phones[2][6:]}", "12/31/2023"),
        (ids[3], "chloë DURAND", f"{phones[3][:3]}-{phones[3][3:6]}-{phones[3][6:]}", "01/01/2020"),
        (ids[4], "pETER green", f"{phones[4][:3]} {phones[4][3:6]} {phones[4][6:]}", "11/19/2019"),
        (ids[5], "françois LEBLANC", f"({phones[5][:3]}){phones[5][3:6]}-{phones[5][6:]}", "04/08/2022"),
        (ids[6], "li WEI", f"{phones[6][:3]}/{phones[6][3:6]}/{phones[6][6:]}", "02/28/2018"),
    ]

    file_specs = [
        ("export_a.csv", "iso-8859-1", source_rows[:3]),
        ("export_b.csv", "cp1252", source_rows[3:5]),
        ("export_c.csv", "utf-8", source_rows[5:]),
    ]

    os.makedirs(RAW_DIR, exist_ok=True)
    for filename, encoding, rows in file_specs:
        text = "\n".join(",".join(map(str, row)) for row in rows) + "\n"
        with open(os.path.join(RAW_DIR, filename), "wb") as f:
            f.write(text.encode(encoding))

    for path in (DB_PATH, CSV_PATH):
        if os.path.exists(path):
            os.remove(path)

    env = os.environ.copy()
    env["LC_ALL"] = "C.UTF-8"
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"The script failed on fresh source files with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.isfile(DB_PATH), "The script did not generate customers.db."
    assert os.path.isfile(CSV_PATH), "The script did not generate recent_customers.csv."

    expected_rows = []
    for filename, encoding, _ in file_specs:
        with open(os.path.join(RAW_DIR, filename), "r", encoding=encoding, newline="") as f:
            for row in csv.reader(f):
                customer_id, name, phone, date = row
                month, day, year = date.split("/")
                expected_rows.append((
                    int(customer_id),
                    name.title(),
                    re.sub(r"\D", "", phone),
                    f"{year}-{month}-{day}",
                ))
    expected_rows.sort(key=lambda row: row[0])

    conn = sqlite3.connect(DB_PATH)
    try:
        integrity = conn.execute("PRAGMA integrity_check;").fetchone()[0]
        assert integrity == "ok", "Generated database failed SQLite integrity check."

        schema = conn.execute("PRAGMA table_info(customers);").fetchall()
        actual_columns = [(row[1], row[2].upper(), row[5]) for row in schema]
        assert actual_columns == [
            ("id", "INTEGER", 1),
            ("full_name", "TEXT", 0),
            ("phone_number", "TEXT", 0),
            ("join_date", "TEXT", 0),
        ], f"Unexpected customers table schema: {schema}"

        actual_rows = conn.execute(
            "SELECT id, full_name, phone_number, join_date FROM customers ORDER BY id"
        ).fetchall()
        assert actual_rows == expected_rows, (
            f"Database rows were not produced by the required normalization pipeline.\n"
            f"Expected: {expected_rows}\nGot: {actual_rows}"
        )
    finally:
        conn.close()

    expected_recent = [
        [str(customer_id), name, phone, date]
        for customer_id, name, phone, date in expected_rows
        if date >= "2020-01-01"
    ]
    with open(CSV_PATH, "r", encoding="utf-8", newline="") as f:
        actual_recent = list(csv.reader(f))

    assert actual_recent == expected_recent, (
        f"Recent-customer export was not correctly filtered and sorted.\n"
        f"Expected: {expected_recent}\nGot: {actual_recent}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
