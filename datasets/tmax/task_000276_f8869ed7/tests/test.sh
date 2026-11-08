#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import pytest

def test_database_updated_correctly():
    db_path = "/home/user/locales.db"
    assert os.path.isfile(db_path), f"Database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Fetch all translations
    cursor.execute("SELECT locale, string_key, translation FROM translations ORDER BY locale, string_key;")
    rows = cursor.fetchall()
    conn.close()

    expected_rows = [
        ('es', 'A_KEY', 'Hola'),
        ('es', 'DESC', 'Esta es una descripción larga'),
        ('es', 'OLD_KEY', 'Viejo'),
        ('es', 'SUBMIT', 'Enviar'),
        ('es', 'TITLE', 'Nuevo Título'),
        ('es', 'Z_KEY', 'Fin'),
        ('fr', 'DESC', 'Description'),
        ('fr', 'SUBMIT', 'Soumettre'),
        ('fr', 'TITLE', 'Titre'),
        ('jp', 'DESC', 'これは説明です'),
        ('jp', 'SUBMIT', '送信'),
        ('jp', 'TITLE', '新しいタイトル')
    ]

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in DB, but got {len(rows)}."
    for expected in expected_rows:
        assert expected in rows, f"Expected row {expected} not found in the database."

def test_index_jp_html_generated():
    html_path = "/home/user/index_jp.html"
    assert os.path.isfile(html_path), f"Generated HTML file {html_path} is missing."

    with open(html_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Check replacements
    assert "<title>新しいタイトル</title>" in content, "Missing or incorrect replacement for __TITLE__ in <title>."
    assert "<h1>新しいタイトル</h1>" in content, "Missing or incorrect replacement for __TITLE__ in <h1>."
    assert "<p>これは説明です</p>" in content, "Missing or incorrect replacement for __DESC__."
    assert "<button>送信</button>" in content, "Missing or incorrect replacement for __SUBMIT__."

    # Check that missing keys are left untouched
    assert "<footer>__MISSING__</footer>" in content, "__MISSING__ placeholder should remain unchanged."

    # The complete template must be preserved, with only known placeholders replaced.
    expected_content = """<!DOCTYPE html>
<html>
<head><title>新しいタイトル</title></head>
<body>
    <h1>新しいタイトル</h1>
    <p>これは説明です</p>
    <button>送信</button>
    <footer>__MISSING__</footer>
</body>
</html>
"""
    assert content == expected_content, "Generated HTML is not the complete localized template."

def test_es_rolling_stats():
    stats_path = "/home/user/es_rolling.txt"
    assert os.path.isfile(stats_path), f"Rolling stats file {stats_path} is missing."

    with open(stats_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    # Expected calculations based on lengths:
    # A_KEY: "Hola" (4) -> 4.0
    # DESC: "Esta es una descripción larga" (29) -> (4+29)/2 = 16.5
    # OLD_KEY: "Viejo" (5) -> (4+29+5)/3 = 12.7
    # SUBMIT: "Enviar" (6) -> (29+5+6)/3 = 13.3
    # TITLE: "Nuevo Título" (12) -> (5+6+12)/3 = 7.7
    # Z_KEY: "Fin" (3) -> (6+12+3)/3 = 7.0

    expected_lines = [
        "A_KEY:4.0",
        "DESC:16.5",
        "OLD_KEY:12.7",
        "SUBMIT:13.3",
        "TITLE:7.7",
        "Z_KEY:7.0"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {stats_path}, got {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch in {stats_path}: expected '{expected}', got '{actual}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
