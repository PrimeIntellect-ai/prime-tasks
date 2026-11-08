#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import sqlite3
import subprocess
from pathlib import Path

import pytest

DB_PATH = "/home/user/locales.db"
GO_PATH = Path("/home/user/clean_i18n.go")
RAW_PATH = Path("/home/user/raw_translations.csv")
CLEANED_PATH = Path("/home/user/cleaned.csv")

ORIGINAL_CLEAN_ROWS = [
    ("greeting_msg", "en", "Hello {{VAR}}, welcome to the system!"),
    ("error_404", "fr", "Page non trouvée pour {{VAR}}"),
    ("checkout_item", "es", "Item {{VAR}} añadido a la cesta."),
    ("promo_code", "de", "Der Code {{VAR}} ist ungültig für {{VAR}}."),
]


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        return list(reader)


def run_cleaner():
    result = subprocess.run(
        ["go", "run", str(GO_PATH)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        "The Go cleaner failed when executed.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert CLEANED_PATH.is_file(), "The Go cleaner did not create /home/user/cleaned.csv."


def normalize_translation(value):
    value = value.strip()
    value = re.sub(r" {2,}", " ", value)
    return re.sub(
        r"\{\{[A-Za-z0-9_]+\}\}|\{[A-Za-z0-9_]+\}|\[[A-Za-z0-9_]+\]",
        "{{VAR}}",
        value,
    )


def test_required_cleaner_artifacts_exist():
    assert GO_PATH.is_file(), "/home/user/clean_i18n.go does not exist."
    assert CLEANED_PATH.is_file(), "/home/user/cleaned.csv does not exist."


def test_cleaned_csv_content():
    rows = read_csv(CLEANED_PATH)
    assert rows, "The cleaned CSV is empty."
    assert rows[0] == ["key", "lang", "translation"], "The cleaned CSV header is incorrect."
    assert [tuple(row) for row in rows[1:]] == ORIGINAL_CLEAN_ROWS, "The cleaned CSV content is incorrect."


def test_go_cleaner_reproduces_and_generalizes():
    raw_backup = RAW_PATH.read_bytes()
    cleaned_backup = CLEANED_PATH.read_bytes()

    try:
        # The submitted Go source must reproduce the required cleaned artifact.
        run_cleaner()
        reproduced = read_csv(CLEANED_PATH)
        assert reproduced[0] == ["key", "lang", "translation"]
        assert [tuple(row) for row in reproduced[1:]] == ORIGINAL_CLEAN_ROWS

        # Exercise the cleaner on unpredictable data so fixed output cannot pass.
        tokens = ["P_" + secrets.token_hex(6) for _ in range(6)]
        placeholders = [
            "{" + tokens[0] + "}",
            "{{" + tokens[1] + "}}",
            "[" + tokens[2] + "]",
            "{" + tokens[3] + "}",
            "{{" + tokens[4] + "}}",
            "[" + tokens[5] + "]",
        ]
        dynamic_rows = [
            ("dynamic_" + secrets.token_hex(4), "en", f"  Alpha {placeholders[0]},     beta {placeholders[1]}! \t"),
            ("dynamic_" + secrets.token_hex(4), "fr", f"\t{placeholders[2]}  et   {placeholders[3]}  "),
            ("dynamic_" + secrets.token_hex(4), "de", "  No placeholders     remain  spaced   "),
            ("dynamic_" + secrets.token_hex(4), "es", f" {placeholders[4]}{placeholders[5]}   juntos "),
        ]

        with open(RAW_PATH, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["key", "lang", "translation"])
            writer.writerows(dynamic_rows)

        run_cleaner()
        actual = read_csv(CLEANED_PATH)
        expected = [["key", "lang", "translation"]] + [
            [key, lang, normalize_translation(translation)]
            for key, lang, translation in dynamic_rows
        ]
        assert actual == expected, f"Cleaner output mismatch. Expected {expected}, got {actual}."
    finally:
        RAW_PATH.write_bytes(raw_backup)
        CLEANED_PATH.write_bytes(cleaned_backup)


def test_database_exists():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."


def test_table_schema():
    assert os.path.isfile(DB_PATH), "Database file missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='translations';")
    table = cursor.fetchone()
    assert table is not None, "Table 'translations' does not exist in the database."

    cursor.execute("PRAGMA table_info(translations);")
    columns = cursor.fetchall()
    col_names = [col[1] for col in columns]
    expected_cols = ["key", "lang", "translation"]

    for col in expected_cols:
        assert col in col_names, f"Column '{col}' is missing from the 'translations' table."

    conn.close()


def test_database_content():
    assert os.path.isfile(DB_PATH), "Database file missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    try:
        cursor.execute("SELECT key, lang, translation FROM translations ORDER BY key;")
        rows = cursor.fetchall()
    except sqlite3.OperationalError:
        pytest.fail("Failed to query the 'translations' table.")
    finally:
        conn.close()

    expected_rows = [
        ("checkout_item", "es", "Item {{VAR}} añadido a la cesta."),
        ("error_404", "fr", "Page non trouvée pour {{VAR}}"),
        ("greeting_msg", "en", "Hello {{VAR}}, welcome to the system!"),
        ("promo_code", "de", "Der Code {{VAR}} ist ungültig für {{VAR}}."),
    ]

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but found {len(rows)}. Ensure the header row was skipped."

    for i, (expected, actual) in enumerate(zip(expected_rows, rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."


def test_header_skipped():
    assert os.path.isfile(DB_PATH), "Database file missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    try:
        cursor.execute("SELECT * FROM translations WHERE key = 'key' OR lang = 'lang';")
        rows = cursor.fetchall()
        assert len(rows) == 0, "The CSV header row was imported into the database. It should be skipped."
    finally:
        conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
