#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import subprocess
from datetime import datetime

import pytest

SOURCE = '/home/user/process_translations.go'
RAW = '/home/user/raw_translations.csv'
INVALID = '/home/user/invalid_rows.csv'
LATEST = '/home/user/latest_translations.jsonl'
BINARY = '/tmp/process_translations_test_bin'


def parse_rfc3339(timestamp_str):
    if timestamp_str.endswith('Z'):
        timestamp_str = timestamp_str[:-1] + '+00:00'
    try:
        return datetime.fromisoformat(timestamp_str)
    except ValueError:
        return None


def compute_expected_states(raw_csv_path):
    expected_invalid = []
    valid_dict = {}
    valid_langs = {'en-us', 'fr-fr', 'es-es', 'de-de', 'ja-jp'}

    with open(raw_csv_path, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        try:
            next(reader)
        except StopIteration:
            return [], []

        for row in reader:
            if len(row) != 5:
                expected_invalid.append(row)
                continue

            timestamp_str, translator_id_str, lang_code_raw, translation_key, translated_text = row
            is_valid = True

            dt = parse_rfc3339(timestamp_str)
            if dt is None:
                is_valid = False

            lang_code = lang_code_raw.lower()
            if lang_code not in valid_langs:
                is_valid = False

            try:
                translator_id = int(translator_id_str)
            except ValueError:
                is_valid = False
                translator_id = None

            if not translation_key:
                is_valid = False
            if not translated_text:
                is_valid = False

            if not is_valid:
                expected_invalid.append(row)
            else:
                key = (lang_code, translation_key)
                current_entry = {
                    'timestamp': timestamp_str,
                    'translator_id': translator_id,
                    'lang_code': lang_code,
                    'translation_key': translation_key,
                    'translated_text': translated_text,
                    '_dt': dt,
                }
                if key not in valid_dict or dt > valid_dict[key]['_dt']:
                    valid_dict[key] = current_entry

    expected_jsonl = []
    for key in sorted(valid_dict.keys()):
        entry = valid_dict[key].copy()
        del entry['_dt']
        expected_jsonl.append(entry)
    return expected_invalid, expected_jsonl


def run_program(binary):
    for path in (INVALID, LATEST):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [binary], cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f'Compiled program exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def assert_invalid_rows(expected_invalid):
    assert os.path.exists(INVALID), f'Output file {INVALID} does not exist.'
    actual_invalid = []
    with open(INVALID, 'r', encoding='utf-8', newline='') as f:
        actual_invalid.extend(csv.reader(f))

    assert len(actual_invalid) == len(expected_invalid), (
        f'Expected {len(expected_invalid)} invalid rows, but found {len(actual_invalid)}.'
    )
    for i, (actual, expected) in enumerate(zip(actual_invalid, expected_invalid)):
        assert actual == expected, (
            f'Row {i + 1} in invalid_rows.csv mismatch. '
            f'Expected: {expected}, Actual: {actual}'
        )


def assert_latest_jsonl(expected_jsonl):
    assert os.path.exists(LATEST), f'Output file {LATEST} does not exist.'
    actual_jsonl = []
    with open(LATEST, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                actual_jsonl.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f'Line {line_num} in {LATEST} is not valid JSON: {line}')

    assert len(actual_jsonl) == len(expected_jsonl), (
        f'Expected {len(expected_jsonl)} valid JSON lines, but found {len(actual_jsonl)}.'
    )
    for i, (actual, expected) in enumerate(zip(actual_jsonl, expected_jsonl)):
        assert actual == expected, (
            f'Line {i + 1} in latest_translations.jsonl mismatch.\n'
            f'Expected: {expected}\nActual:   {actual}'
        )


@pytest.fixture(scope='module')
def compiled_program():
    assert os.path.isfile(SOURCE), f'Go source file {SOURCE} is missing or is not a regular file.'
    with open(SOURCE, 'r', encoding='utf-8') as f:
        source_text = f.read()

    # Whole-file reads defeat the required streaming processing model.
    assert not re.search(r'\.\s*ReadAll\s*\(', source_text), 'The input must be processed as a stream, not with ReadAll.'
    assert not re.search(r'\b(?:os|ioutil)\s*\.\s*ReadFile\s*\(', source_text), 'The input must be processed as a stream, not with ReadFile.'

    build = subprocess.run(
        ['go', 'build', '-o', BINARY, SOURCE],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert build.returncode == 0, f'Go source does not compile:\n{build.stderr}'
    assert os.path.isfile(BINARY), 'go build did not produce an executable.'
    return BINARY


@pytest.fixture(scope='module')
def expected_data(compiled_program):
    assert os.path.exists(RAW), f'Input file {RAW} is missing.'
    expected = compute_expected_states(RAW)
    run_program(compiled_program)
    return expected


def test_invalid_rows_csv(expected_data):
    expected_invalid, _ = expected_data
    assert_invalid_rows(expected_invalid)


def test_latest_translations_jsonl(expected_data):
    _, expected_jsonl = expected_data
    assert_latest_jsonl(expected_jsonl)


def test_program_processes_unseen_input(compiled_program):
    token = secrets.token_hex(10)
    original_raw = None
    if os.path.exists(RAW):
        with open(RAW, 'rb') as f:
            original_raw = f.read()

    rows = [
        ['timestamp', 'translator_id', 'lang_code', 'translation_key', 'translated_text'],
        ['2025-01-01T00:00:00Z', '700', 'EN-US', 'dynamic_' + token, 'old value'],
        ['2025-01-03T00:00:00Z', '701', 'en-us', 'dynamic_' + token, 'new, quoted value'],
        ['2025-01-03T00:00:00Z', '702', 'EN-US', 'dynamic_' + token, 'same-time later row'],
        ['2025-02-01T12:30:00+02:00', '-9', 'FR-FR', 'alpha_' + token, 'ligne\nmultiple'],
        ['2025-02-01T10:00:00Z', '55', 'de-DE', 'zeta_' + token, 'Deutsch'],
        ['2025-02-02T10:00:00Z', '56', 'JA-JP', 'kana_' + token, '日本語'],
        ['not-a-time-' + token, '12', 'es-es', 'bad_time', 'Hola'],
        ['2025-03-01T00:00:00Z', 'not-' + token, 'es-es', 'bad_id', 'Hola'],
        ['2025-03-01T00:00:00Z', '13', 'it-it', 'bad_lang', 'Ciao'],
        ['2025-03-01T00:00:00Z', '14', 'es-es', '', 'empty key'],
        ['2025-03-01T00:00:00Z', '15', 'es-es', 'empty_text', ''],
    ]

    # Add enough non-fixed data to ensure the program really consumes the CSV,
    # while keeping one deduplicated result per generated key.
    for i in range(2000):
        rows.append([
            f'2024-01-{(i % 28) + 1:02d}T00:00:00Z',
            str(1000 + i),
            'ES-ES' if i % 2 else 'es-es',
            f'bulk_{i % 17}_{token}',
            f'value {i}',
        ])

    try:
        with open(RAW, 'w', encoding='utf-8', newline='') as f:
            writer = csv.writer(f, lineterminator='\n')
            writer.writerows(rows)

        expected_invalid, expected_jsonl = compute_expected_states(RAW)
        run_program(compiled_program)
        assert_invalid_rows(expected_invalid)
        assert_latest_jsonl(expected_jsonl)
    finally:
        if original_raw is not None:
            with open(RAW, 'wb') as f:
                f.write(original_raw)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
