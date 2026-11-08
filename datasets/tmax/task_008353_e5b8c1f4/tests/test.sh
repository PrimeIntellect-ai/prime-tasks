#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import secrets
import sqlite3
import subprocess
from collections import Counter

RAW_PATH = "/home/user/raw_translations.jsonl"
BINARY_PATH = "/home/user/reshaper"


def parse_jsonl(data):
    objects = []
    for line in data.decode("utf-8").splitlines():
        if line.strip():
            objects.append(json.loads(line))
    return objects


def expected_rows(objects):
    return [
        (obj["id"], locale, obj[locale])
        for obj in objects
        for locale in ("en", "fr", "ja")
    ]


def parse_csv_output(data):
    text = data.decode("utf-8")
    return [tuple(row) for row in csv.reader(io.StringIO(text, newline=""))]


def run_reshaper(input_data):
    result = subprocess.run(
        [BINARY_PATH],
        input=input_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, (
        f"reshaper exited with status {result.returncode}: "
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )
    return parse_csv_output(result.stdout)


def test_c_program_exists():
    assert os.path.exists("/home/user/reshaper.c"), "/home/user/reshaper.c does not exist"
    assert os.path.exists("/home/user/reshaper"), "/home/user/reshaper (compiled binary) does not exist"
    assert os.access("/home/user/reshaper", os.X_OK), "/home/user/reshaper is not executable"
    with open("/home/user/reshaper", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/reshaper is not a compiled executable"


def test_reshaper_processes_supplied_stdin_and_decodes_unicode():
    token = secrets.token_hex(8)
    objects = [
        {
            "id": f"dynamic_{token}_a",
            "en": f"English {token}",
            "fr": f"Café {token}",
            "ja": "東京語",
        },
        {
            "id": f"dynamic_{token}_b",
            "en": f"Second {token}",
            "fr": f"Été {token}",
            "ja": "雪月花",
        },
    ]
    lines = []
    for obj in objects:
        fields = [json.dumps(obj[key], ensure_ascii=True) for key in ("id", "en", "fr", "ja")]
        lines.append(
            '{"id":%s,"en":%s,"fr":%s,"ja":%s}' % tuple(fields)
        )
    input_data = ("\n".join(lines) + "\n").encode("ascii")
    actual = run_reshaper(input_data)
    assert Counter(actual) == Counter(expected_rows(objects)), (
        f"reshaper output did not match its supplied stdin. Got: {actual!r}"
    )


def test_reshaper_on_raw_input():
    with open(RAW_PATH, "rb") as f:
        raw_data = f.read()
    objects = parse_jsonl(raw_data)
    actual = run_reshaper(raw_data)
    assert Counter(actual) == Counter(expected_rows(objects)), (
        f"reshaper output does not match {RAW_PATH}. Got: {actual!r}"
    )


def test_csv_output_exists():
    assert os.path.exists("/home/user/long_translations.csv"), "/home/user/long_translations.csv does not exist"


def test_csv_contents_match_input():
    with open(RAW_PATH, "rb") as f:
        objects = parse_jsonl(f.read())
    with open("/home/user/long_translations.csv", "rb") as f:
        actual = parse_csv_output(f.read())
    assert Counter(actual) == Counter(expected_rows(objects)), (
        f"long_translations.csv does not contain the reshaped input rows. Got: {actual!r}"
    )


def test_sqlite_db_exists_and_schema():
    db_path = "/home/user/translations.db"
    assert os.path.exists(db_path), f"{db_path} does not exist"

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check table existence
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='i18n';")
    assert cursor.fetchone() is not None, "Table 'i18n' does not exist in translations.db"

    # Check row counts
    cursor.execute("SELECT COUNT(*) FROM i18n;")
    count = cursor.fetchone()[0]
    # 4 JSON lines * 3 locales (en, fr, ja) = 12
    assert count == 12, f"Expected 12 rows in i18n table, got {count}"

    cursor.execute("PRAGMA table_info(i18n)")
    columns = [(row[1], row[2].upper()) for row in cursor.fetchall()]
    assert columns == [
        ("msg_id", "TEXT"),
        ("locale", "TEXT"),
        ("translation", "TEXT"),
    ], f"Unexpected i18n schema: {columns!r}"

    with open(RAW_PATH, "rb") as f:
        objects = parse_jsonl(f.read())
    cursor.execute("SELECT msg_id, locale, translation FROM i18n")
    rows = [tuple(row) for row in cursor.fetchall()]
    assert Counter(rows) == Counter(expected_rows(objects)), (
        f"Database rows do not match the input translations. Got: {rows!r}"
    )

    conn.close()


def test_ja_check_txt():
    txt_path = "/home/user/ja_check.txt"
    assert os.path.exists(txt_path), f"{txt_path} does not exist"

    with open(txt_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_lines = [
        "farewell|さようなら",
        "greeting|こんにちは",
        "thanks|ありがとう",
        "yes|はい"
    ]

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, f"Contents of {txt_path} do not match the expected output. Got:\n{content}"

    conn = sqlite3.connect("/home/user/translations.db")
    rows = conn.execute(
        "SELECT msg_id, translation FROM i18n WHERE locale='ja' ORDER BY msg_id"
    ).fetchall()
    conn.close()
    derived_lines = [f"{msg_id}|{translation}" for msg_id, translation in rows]
    assert actual_lines == derived_lines, "ja_check.txt is not the requested database query output"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
