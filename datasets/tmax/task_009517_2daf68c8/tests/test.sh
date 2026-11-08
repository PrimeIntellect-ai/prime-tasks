#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import subprocess
import pytest

PROCESS_C = '/home/user/process.c'
EXECUTABLE = '/tmp/process_submission'
BASE_CSV = '/home/user/base_strings.csv'
TRANS_CSV = '/home/user/translations_raw.csv'
SQL_FILE = '/home/user/bulk_import.sql'


def run_program():
    if os.path.exists(SQL_FILE):
        os.remove(SQL_FILE)
    subprocess.run([EXECUTABLE], cwd='/home/user', check=True, timeout=10)


@pytest.fixture(scope='session', autouse=True)
def compile_and_run_submission():
    assert os.path.isfile(PROCESS_C), f"Expected C source file {PROCESS_C} does not exist."

    with open(BASE_CSV, 'rb') as f:
        original_base = f.read()
    with open(TRANS_CSV, 'rb') as f:
        original_translations = f.read()

    subprocess.run(
        ['gcc', PROCESS_C, '-o', EXECUTABLE],
        check=True,
        timeout=20,
    )
    run_program()

    try:
        yield
    finally:
        with open(BASE_CSV, 'wb') as f:
            f.write(original_base)
        with open(TRANS_CSV, 'wb') as f:
            f.write(original_translations)
        run_program()


def test_process_c_exists():
    assert os.path.isfile(PROCESS_C), f"Expected C source file {PROCESS_C} does not exist."


def test_bulk_import_sql_exists():
    assert os.path.isfile(SQL_FILE), f"Expected output file {SQL_FILE} does not exist."


def test_bulk_import_sql_content():
    assert os.path.isfile(SQL_FILE), f"Expected output file {SQL_FILE} does not exist."

    with open(SQL_FILE, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected exactly 4 non-empty lines in {SQL_FILE}, but found {len(lines)}."

    expected_lines = {
        "INSERT INTO loc_data (string_id, locale, word_count, translated_text) VALUES ('ERR_01', 'fr', 3, 'Fichier non trouvé');",
        "INSERT INTO loc_data (string_id, locale, word_count, translated_text) VALUES ('BTN_OK', 'fr', 1, 'D''accord');",
        "INSERT INTO loc_data (string_id, locale, word_count, translated_text) VALUES ('MSG_GREET', 'es', 5, 'Bienvenido al sistema');",
        "INSERT INTO loc_data (string_id, locale, word_count, translated_text) VALUES ('MSG_BYE', 'it', 1, 'Arrivederci');"
    }

    actual_lines = set(lines)
    missing_lines = expected_lines - actual_lines
    extra_lines = actual_lines - expected_lines

    error_msg = []
    if missing_lines:
        error_msg.append("Missing expected lines:\n" + "\n".join(missing_lines))
    if extra_lines:
        error_msg.append("Unexpected extra lines:\n" + "\n".join(extra_lines))

    assert not missing_lines and not extra_lines, "\n".join(error_msg)


def test_program_processes_changed_inputs():
    with open(BASE_CSV, 'w', encoding='utf-8', newline='') as f:
        f.write('ITEM_A,Alpha beta gamma\nITEM_B,Single\n')

    with open(TRANS_CSV, 'w', encoding='utf-8', newline='') as f:
        f.write(
            'ITEM_A,xx,Outdated,10\n'
            "ITEM_A,xx,L'été arrive,25\n"
            'ITEM_B,yy,Older,2\n'
            'ITEM_B,yy,Newest value,8\n'
        )

    run_program()

    base = {}
    with open(BASE_CSV, newline='', encoding='utf-8') as f:
        for string_id, default_text in csv.reader(f):
            base[string_id] = len(default_text.split())

    latest = {}
    with open(TRANS_CSV, newline='', encoding='utf-8') as f:
        for string_id, locale, translated_text, timestamp in csv.reader(f):
            key = (string_id, locale)
            timestamp = int(timestamp)
            if key not in latest or timestamp > latest[key][0]:
                latest[key] = (timestamp, translated_text)

    expected = set()
    for (string_id, locale), (_, translated_text) in latest.items():
        escaped = translated_text.replace("'", "''")
        expected.add(
            "INSERT INTO loc_data (string_id, locale, word_count, translated_text) "
            f"VALUES ('{string_id}', '{locale}', {base[string_id]}, '{escaped}');"
        )

    assert os.path.isfile(SQL_FILE), f"Expected output file {SQL_FILE} does not exist after executing the C program."
    with open(SQL_FILE, 'r', encoding='utf-8') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected)
    assert set(actual_lines) == expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
