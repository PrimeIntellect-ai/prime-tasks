#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import sqlite3
import subprocess
from decimal import Decimal


def test_clean_data_csv():
    csv_path = "/home/user/clean_data.csv"
    assert os.path.isfile(csv_path), f"Expected output file {csv_path} does not exist."

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "MaskedEmail,TotalValue",
        "b***@yahoo.com,225.00",
        "a***@gmail.com,200.00",
        "c***@company.co.uk,75.25",
        "d***@short.com,10.00"
    ]

    assert lines == expected_lines, "The content of clean_data.csv does not match the expected aggregated and sorted output."


def test_analytics_db():
    db_path = "/home/user/analytics.db"
    assert os.path.isfile(db_path), f"Expected database file {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='UserTotals';")
    table_exists = cursor.fetchone()
    assert table_exists is not None, "Table 'UserTotals' does not exist in analytics.db."

    cursor.execute("SELECT MaskedEmail, TotalValue FROM UserTotals ORDER BY TotalValue DESC;")
    rows = cursor.fetchall()

    expected_rows = [
        ("b***@yahoo.com", 225.0),
        ("a***@gmail.com", 200.0),
        ("c***@company.co.uk", 75.25),
        ("d***@short.com", 10.0)
    ]

    formatted_rows = [(row[0], round(float(row[1]), 2)) for row in rows]
    expected_formatted = [(row[0], round(float(row[1]), 2)) for row in expected_rows]

    assert formatted_rows == expected_formatted, "The data in UserTotals table does not match the expected values."
    conn.close()


def test_c_program_exists():
    assert os.path.isfile("/home/user/process.c"), "/home/user/process.c is missing."
    assert os.path.isfile("/home/user/process"), "The compiled executable /home/user/process is missing."
    assert os.access("/home/user/process", os.X_OK), "/home/user/process is not executable."
    with open("/home/user/process", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/process is not a compiled ELF executable."


def expected_output(records):
    email_re = re.compile(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")
    totals = {}
    for email, value in records:
        if email_re.fullmatch(email) is None:
            continue
        local, domain = email.split("@", 1)
        masked = local[0] + "***@" + domain
        totals[masked] = totals.get(masked, Decimal("0")) + Decimal(value)
    ordered = sorted(totals.items(), key=lambda item: (-item[1], item[0]))
    return ["MaskedEmail,TotalValue"] + [f"{email},{value:.2f}" for email, value in ordered]


def run_fixture(executable, records):
    with open("/home/user/raw_data.csv", "w", newline="") as f:
        f.write("DateString,Email,TransactionValue\n")
        for index, (email, value) in enumerate(records):
            f.write(f"2026-01-{index + 1:02d} 12:00:00,{email},{value}\n")

    result = subprocess.run([executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=10)
    assert result.returncode == 0, (
        f"{executable} failed on a verifier-generated input: {result.stderr}"
    )
    assert os.path.isfile("/home/user/clean_data.csv"), "Program did not create clean_data.csv."
    with open("/home/user/clean_data.csv", "r") as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected_output(records), (
        "Program output is incorrect for a verifier-generated CSV.\n"
        f"Expected: {expected_output(records)}\nActual: {actual}"
    )


def test_program_behavior_on_generated_inputs():
    raw_path = "/home/user/raw_data.csv"
    clean_path = "/home/user/clean_data.csv"
    with open(raw_path, "rb") as f:
        original_raw = f.read()
    original_clean = None
    if os.path.exists(clean_path):
        with open(clean_path, "rb") as f:
            original_clean = f.read()

    token = secrets.token_hex(6)
    domain_a = f"a{token}.example.com"
    domain_b = f"b{token}.example.net"
    domain_c = f"sub{token}.company.co.uk"

    fixture_one = [
        (f"alpha.one@{domain_a}", "10.25"),
        (f"atom+tag@{domain_a}", "4.75"),
        (f"bob_1@{domain_b}", "8.00"),
        (f"b.two@{domain_b}", "7.00"),
        (f"z%last@{domain_c}", "30.50"),
        (f"q@q{token}.org", "2.25"),
        ("missing-at-sign", "9999.00"),
        ("bad@under_score.com", "8888.00"),
        ("bad@example.c", "7777.00"),
        ("@example.com", "6666.00"),
        ("ok@example.com extra", "5555.00"),
    ]

    fixture_two = [
        (f"mary@new{token}.io", "1.10"),
        (f"m.other@new{token}.io", "2.20"),
        (f"Alice@case{token}.COM", "12.00"),
        (f"adam@case{token}.COM", "12.00"),
        (f"x@tiny{token}.dev", "3.30"),
        ("no-domain@", "9000.00"),
        ("space @example.com", "8000.00"),
    ]

    rebuilt = "/tmp/process_rebuilt"
    try:
        run_fixture("/home/user/process", fixture_one)

        compile_result = subprocess.run(
            ["gcc", "-o", rebuilt, "/home/user/process.c"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert compile_result.returncode == 0, (
            "process.c does not compile with gcc: " + compile_result.stderr
        )

        symbols = subprocess.run(
            ["nm", "-D", rebuilt], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=10
        )
        assert symbols.returncode == 0, "Could not inspect the rebuilt executable."
        assert "regcomp" in symbols.stdout and "regexec" in symbols.stdout, (
            "The C program does not use POSIX regcomp/regexec for email validation."
        )

        run_fixture(rebuilt, fixture_two)
    finally:
        with open(raw_path, "wb") as f:
            f.write(original_raw)
        if original_clean is None:
            if os.path.exists(clean_path):
                os.remove(clean_path)
        else:
            with open(clean_path, "wb") as f:
                f.write(original_clean)
        if os.path.exists(rebuilt):
            os.remove(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
