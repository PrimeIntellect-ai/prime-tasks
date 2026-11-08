#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import hashlib
import pytest

def get_expected_data():
    original_tm = [
        ("Hello", "es", "Hola"),
        ("Save changes", "fr", "Enregistrer les modifications"),
        ("Cancel", "de", "Abbrechen")
    ]

    incoming_lines = [
        r'{"en": "Hello", "locale": "fr", "trans": "Bonjour"}',
        r'{"en": "Save changes", "locale": "fr", "trans": "Enregistrer les modifications"}',
        r'{"en": "Welcome back", "locale": "es", "trans": "Bienvenido de nuevo \u00Z"}',
        r'{"en": "File not found", "locale": "de", "trans": "Datei nicht gefunden"}',
        r'{"en": "Loading...", "locale": "es", "trans": "Cargando..."}',
        r'{"en": "Retry", "locale": "es", "trans": "Reintentar"}',
        r'{"en": "Skip", "locale": "de", "trans": "Überspringen"}',
        r'{"en": "Delete account", "locale": "de", "trans": "Konto l\u00-schen"}',
        r'{"en": "Next", "locale": "fr", "trans": "Suivant"}',
        r'{"en": "Previous", "locale": "fr", "trans": "Précédent"}'
    ]

    errors = []
    parsed_incoming = []
    for line in incoming_lines:
        try:
            parsed = json.loads(line)
            parsed_incoming.append(parsed)
        except json.JSONDecodeError:
            errors.append(line)

    tm_keys = set()
    expected_tm = []
    for en, loc, trans in original_tm:
        str_id = hashlib.md5(en.encode('utf-8')).hexdigest()
        tm_keys.add((str_id, loc))
        expected_tm.append([str_id, en, loc, trans])

    new_translations = []
    for item in parsed_incoming:
        en = item['en']
        loc = item['locale']
        trans = item['trans']
        str_id = hashlib.md5(en.encode('utf-8')).hexdigest()

        if (str_id, loc) not in tm_keys:
            tm_keys.add((str_id, loc))
            expected_tm.append([str_id, en, loc, trans])
            new_translations.append({'str_id': str_id, 'en': en, 'locale': loc, 'trans': trans})

    # QA Sample
    locales = {}
    for item in new_translations:
        locales.setdefault(item['locale'], []).append(item)

    qa_sample = []
    for loc in sorted(locales.keys()):
        items = locales[loc]
        items.sort(key=lambda x: x['str_id'])
        for item in items[:2]:
            qa_sample.append([loc, item['str_id'], item['trans']])

    return expected_tm, errors, qa_sample

def test_errors_log():
    errors_path = '/home/user/errors.log'
    assert os.path.isfile(errors_path), f"Errors log file missing at {errors_path}"

    _, expected_errors, _ = get_expected_data()

    with open(errors_path, 'r', encoding='utf-8') as f:
        actual_errors = [line.strip('\n') for line in f.readlines()]

    assert actual_errors == expected_errors, "Errors log does not contain the exact expected malformed lines"

def test_tm_master_csv():
    tm_path = '/home/user/tm_master.csv'
    assert os.path.isfile(tm_path), f"Master TM file missing at {tm_path}"

    expected_tm, _, _ = get_expected_data()

    with open(tm_path, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["string_id", "en_source", "locale", "translation"], "Incorrect header in tm_master.csv"

        actual_tm = list(reader)

    assert len(actual_tm) == len(expected_tm), f"Expected {len(expected_tm)} rows in tm_master.csv, got {len(actual_tm)}"
    for i, (actual, expected) in enumerate(zip(actual_tm, expected_tm)):
        assert actual == expected, f"Row {i+1} in tm_master.csv mismatch. Expected {expected}, got {actual}"

def test_qa_sample_csv():
    qa_path = '/home/user/qa_sample.csv'
    assert os.path.isfile(qa_path), f"QA sample file missing at {qa_path}"

    _, _, expected_qa = get_expected_data()

    with open(qa_path, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["locale", "string_id", "translation"], "Incorrect header in qa_sample.csv"

        actual_qa = list(reader)

    assert len(actual_qa) == len(expected_qa), f"Expected {len(expected_qa)} rows in qa_sample.csv, got {len(actual_qa)}"
    for i, (actual, expected) in enumerate(zip(actual_qa, expected_qa)):
        assert actual == expected, f"Row {i+1} in qa_sample.csv mismatch. Expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
