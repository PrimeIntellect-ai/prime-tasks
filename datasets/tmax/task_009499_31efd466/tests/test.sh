#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import base64
import csv
import re
import secrets
import subprocess
from pathlib import Path

RAW_FILE = Path('/home/user/raw_translations.jsonl')
CSV_FILE = Path('/home/user/processed_metrics.csv')
PROJECT = Path('/home/user/loc_etl')


def expected_from_raw(raw_file):
    seen_tx = set()
    windows = {}
    expected_rows = []

    with open(raw_file, 'r', encoding='utf-8') as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)
            tx_id = record['tx_id']
            if tx_id in seen_tx:
                continue
            seen_tx.add(tx_id)

            lang = record['lang']
            charset = record['charset']
            py_charset = 'cp1252' if charset.lower() == 'windows-1252' else charset
            raw_bytes = base64.b64decode(record['payload_b64'])
            text = raw_bytes.decode(py_charset)
            char_count = len(text)

            windows.setdefault(lang, []).append(char_count)
            if len(windows[lang]) > 3:
                windows[lang].pop(0)

            avg = sum(windows[lang]) / len(windows[lang])
            expected_rows.append([str(tx_id), lang, f'{avg:.1f}'])

    return expected_rows


def assert_csv_matches(raw_file, csv_file):
    expected_rows = expected_from_raw(raw_file)
    assert os.path.exists(csv_file), f'Output file {csv_file} does not exist.'

    actual_rows = []
    with open(csv_file, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['tx_id', 'lang', 'avg_char_count'], f'Incorrect CSV header: {header}'
        for row in reader:
            if row:
                actual_rows.append(row)

    assert len(actual_rows) == len(expected_rows), f'Expected {len(expected_rows)} data rows, got {len(actual_rows)}'
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f'Row {i+1} mismatch: expected {expected}, got {actual}'


def test_1_original_processed_metrics_csv():
    # Preserve the original verifier's exact behavioral check on the supplied input.
    assert_csv_matches(RAW_FILE, CSV_FILE)


def test_2_is_rust_streaming_application():
    assert PROJECT.is_dir(), f'Rust project directory {PROJECT} does not exist.'
    assert (PROJECT / 'Cargo.toml').is_file(), 'Cargo.toml is missing.'
    assert (PROJECT / 'src' / 'main.rs').is_file(), 'src/main.rs is missing.'

    rust_files = list(PROJECT.rglob('*.rs'))
    assert rust_files, 'No Rust source files were found.'
    source = '\n'.join(path.read_text(encoding='utf-8', errors='replace') for path in rust_files)

    assert re.search(r'\bBufRead\b', source), 'Rust application must use buffered, line-oriented input.'
    assert re.search(r'\.lines\s*\(|\bread_line\s*\(', source), 'Rust application must process the JSONL input line-by-line.'
    forbidden = [r'\bread_to_string\s*\(', r'\bread_to_end\s*\(', r'fs::read_to_string\s*\(', r'fs::read\s*\(']
    assert not any(re.search(pattern, source) for pattern in forbidden), 'Application appears to load the entire input instead of streaming it.'


def test_3_run_application_on_unseen_input():
    nonce = secrets.randbelow(800_000_000) + 100_000_000
    records = [
        (nonce + 1, 'es', 'utf-8', 'x' * (nonce % 7 + 2)),
        (nonce + 2, 'ja', 'shift_jis', 'こんにちは'),
        (nonce + 3, 'es', 'windows-1252', 'Adiós señor'),
        (nonce + 1, 'fr', 'utf-8', 'THIS DUPLICATE MUST BE IGNORED'),
        (nonce + 4, 'es', 'utf-8', 'mañana'),
        (nonce + 5, 'fr', 'utf-8', 'élève'),
        (nonce + 6, 'es', 'utf-8', 'z' * (nonce % 11 + 13)),
        (nonce + 7, 'ja', 'shift_jis', 'さようなら'),
        (nonce + 8, 'fr', 'windows-1252', 'Crème brûlée'),
        (nonce + 9, 'es', 'utf-8', 'último registro'),
    ]

    with open(RAW_FILE, 'w', encoding='utf-8') as f:
        for tx_id, lang, charset, text in records:
            codec = 'cp1252' if charset == 'windows-1252' else charset
            payload = base64.b64encode(text.encode(codec)).decode('ascii')
            f.write(json.dumps({
                'tx_id': tx_id,
                'lang': lang,
                'charset': charset,
                'payload_b64': payload,
            }) + '\n')

    if CSV_FILE.exists():
        CSV_FILE.unlink()

    result = subprocess.run(
        ['cargo', 'run', '--quiet'],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, f'Rust application failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    assert_csv_matches(RAW_FILE, CSV_FILE)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
