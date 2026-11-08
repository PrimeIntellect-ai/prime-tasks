#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import sqlite3
from collections import Counter

WIDE_CSV = "/home/user/locales_wide.csv"
LONG_CSV = "/home/user/locales_long.csv"
FEATURES_CSV = "/home/user/locales_features.csv"
STATS_CSV = "/home/user/locales_stats.csv"
DB_FILE = "/home/user/loc_metrics.db"

MATH_SYMBOLS = {'∑', '√', '≈', '∞', '±'}

def get_expected_data():
    if not os.path.exists(WIDE_CSV):
        return []

    expected_long = []
    with open(WIDE_CSV, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        langs = header[1:]
        for row in reader:
            msg_id = row[0]
            for i, lang in enumerate(langs):
                expected_long.append({
                    "msg_id": msg_id,
                    "lang": lang,
                    "translation": row[i+1]
                })
    return expected_long

def get_expected_stats():
    stats = {}
    for item in get_expected_data():
        lang = item["lang"]
        trans = item["translation"]
        if lang not in stats:
            stats[lang] = {"lens": [], "math": 0}
        stats[lang]["lens"].append(len(trans))
        stats[lang]["math"] += sum(1 for c in trans if c in MATH_SYMBOLS)

    expected_stats = []
    for lang in sorted(stats.keys()):
        avg_len = sum(stats[lang]["lens"]) / len(stats[lang]["lens"])
        expected_stats.append({
            "lang": lang,
            "avg_char_len": f"{avg_len:.2f}",
            "total_math_sym": str(stats[lang]["math"])
        })
    return expected_stats

def test_locales_long_csv():
    assert os.path.isfile(LONG_CSV), f"{LONG_CSV} is missing"

    with open(LONG_CSV, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ["msg_id", "lang", "translation"], f"Incorrect header in {LONG_CSV}"
        rows = list(reader)

    expected = get_expected_data()
    assert len(rows) == len(expected), f"Expected {len(expected)} rows in {LONG_CSV}, got {len(rows)}"

    for i, row in enumerate(rows):
        assert row[0] == expected[i]["msg_id"]
        assert row[1] == expected[i]["lang"]
        assert row[2] == expected[i]["translation"]

def test_locales_features_csv():
    assert os.path.isfile(FEATURES_CSV), f"{FEATURES_CSV} is missing"

    with open(FEATURES_CSV, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ["msg_id", "lang", "translation", "char_len", "math_sym_count"], f"Incorrect header in {FEATURES_CSV}"
        rows = list(reader)

    expected = get_expected_data()
    assert len(rows) == len(expected), f"Expected {len(expected)} rows in {FEATURES_CSV}, got {len(rows)}"

    for i, row in enumerate(rows):
        trans = expected[i]["translation"]
        char_len = len(trans)
        math_count = sum(1 for c in trans if c in MATH_SYMBOLS)

        assert row[0] == expected[i]["msg_id"]
        assert row[1] == expected[i]["lang"]
        assert row[2] == trans
        assert int(row[3]) == char_len, f"Incorrect char_len for {trans}"
        assert int(row[4]) == math_count, f"Incorrect math_sym_count for {trans}"

def test_locales_stats_csv():
    assert os.path.isfile(STATS_CSV), f"{STATS_CSV} is missing"
    expected_stats = get_expected_stats()

    with open(STATS_CSV, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ["lang", "avg_char_len", "total_math_sym"], f"Incorrect header in {STATS_CSV}"
        rows = list(reader)

    assert len(rows) == len(expected_stats), f"Expected {len(expected_stats)} rows in {STATS_CSV}"

    for i, row in enumerate(rows):
        assert row[0] == expected_stats[i]["lang"]
        assert row[1] == expected_stats[i]["avg_char_len"]
        assert row[2] == expected_stats[i]["total_math_sym"]

def test_sqlite_database():
    assert os.path.isfile(DB_FILE), f"{DB_FILE} is missing"

    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()

    # Check translations table
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='translations'")
    assert cursor.fetchone() is not None, "Table 'translations' is missing"

    cursor.execute("SELECT count(*) FROM translations")
    count = cursor.fetchone()[0]
    expected = get_expected_data()
    assert count == len(expected), f"Expected {len(expected)} rows in translations table, got {count}"

    # Verify the required translations schema and every imported value.
    cursor.execute("PRAGMA table_info(translations)")
    translation_schema = [(r[1], r[2].upper()) for r in cursor.fetchall()]
    assert translation_schema == [
        ("msg_id", "TEXT"),
        ("lang", "TEXT"),
        ("translation", "TEXT"),
        ("char_len", "INTEGER"),
        ("math_sym_count", "INTEGER")
    ], f"Incorrect translations schema: {translation_schema}"

    expected_translation_rows = Counter(
        (item["msg_id"], item["lang"], item["translation"],
         len(item["translation"]),
         sum(1 for c in item["translation"] if c in MATH_SYMBOLS))
        for item in expected
    )
    cursor.execute("SELECT msg_id, lang, translation, char_len, math_sym_count FROM translations")
    actual_translation_rows = Counter(cursor.fetchall())
    assert actual_translation_rows == expected_translation_rows, "translations does not contain the exact feature data"

    cursor.execute("SELECT DISTINCT typeof(msg_id), typeof(lang), typeof(translation), typeof(char_len), typeof(math_sym_count) FROM translations")
    assert cursor.fetchall() == [("text", "text", "text", "integer", "integer")], "Incorrect SQLite storage types in translations"

    # Check language_stats table
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='language_stats'")
    assert cursor.fetchone() is not None, "Table 'language_stats' is missing"

    cursor.execute("SELECT count(*) FROM language_stats")
    count = cursor.fetchone()[0]
    langs = set(item["lang"] for item in expected)
    assert count == len(langs), f"Expected {len(langs)} rows in language_stats table, got {count}"

    # Check specific value
    cursor.execute("SELECT avg_char_len FROM language_stats WHERE lang='es'")
    es_avg = cursor.fetchone()
    assert es_avg is not None, "Missing 'es' row in language_stats"

    es_lens = [len(item["translation"]) for item in expected if item["lang"] == "es"]
    expected_es_avg = round(sum(es_lens) / len(es_lens), 2)
    assert abs(float(es_avg[0]) - expected_es_avg) < 0.01, f"Expected avg_char_len for 'es' to be {expected_es_avg}, got {es_avg[0]}"

    # Verify the required language_stats schema and all imported statistics.
    cursor.execute("PRAGMA table_info(language_stats)")
    stats_schema = [(r[1], r[2].upper()) for r in cursor.fetchall()]
    assert stats_schema == [
        ("lang", "TEXT"),
        ("avg_char_len", "REAL"),
        ("total_math_sym", "INTEGER")
    ], f"Incorrect language_stats schema: {stats_schema}"

    expected_stats = get_expected_stats()
    cursor.execute("SELECT lang, avg_char_len, total_math_sym FROM language_stats")
    actual_stats = cursor.fetchall()
    assert Counter(row[0] for row in actual_stats) == Counter(row["lang"] for row in expected_stats), "Incorrect languages in language_stats"
    actual_by_lang = {row[0]: row[1:] for row in actual_stats}
    for row in expected_stats:
        actual_avg, actual_total = actual_by_lang[row["lang"]]
        assert abs(float(actual_avg) - float(row["avg_char_len"])) < 0.000001, f"Incorrect average for {row['lang']}"
        assert actual_total == int(row["total_math_sym"]), f"Incorrect total_math_sym for {row['lang']}"

    cursor.execute("SELECT DISTINCT typeof(lang), typeof(avg_char_len), typeof(total_math_sym) FROM language_stats")
    assert cursor.fetchall() == [("text", "real", "integer")], "Incorrect SQLite storage types in language_stats"

    conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
