#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess
import unicodedata
from pathlib import Path

HOME = Path('/home/user')
CSV_INPUT = HOME / 'reviews_part1.csv'
JSON_INPUT = HOME / 'reviews_part2.json'
OUTPUT = HOME / 'cleaned_product_stats.csv'


def read_output():
    assert OUTPUT.is_file(), f'Output file is missing: {OUTPUT}'
    with OUTPUT.open('r', encoding='utf-8', newline='') as f:
        rows = list(csv.reader(f))
    assert len(rows) > 0, 'The output CSV is empty.'
    expected_headers = ['product_id', 'review_count', 'avg_word_count']
    assert rows[0] == expected_headers, f'Expected headers {expected_headers}, but got {rows[0]}'
    return rows


def check_original_output():
    rows = read_output()
    data_rows = rows[1:]
    assert len(data_rows) == 4, f'Expected 4 data rows, but got {len(data_rows)}'

    parsed_rows = []
    for row in data_rows:
        assert len(row) == 3, f'Row has incorrect number of columns: {row}'
        product_id, review_count, avg_word_count = row
        parsed_rows.append((product_id, int(review_count), float(avg_word_count)))

    expected_data = [
        ('p1', 2, 3.00),
        ('p3', 2, 1.50),
        ('p2', 1, 3.00),
        ('p4', 1, 5.00),
    ]
    for i, (actual, expected) in enumerate(zip(parsed_rows, expected_data)):
        assert actual[0] == expected[0], f'Row {i+1}: Expected product_id {expected[0]}, got {actual[0]}'
        assert actual[1] == expected[1], f'Row {i+1}: Expected review_count {expected[1]}, got {actual[1]}'
        assert abs(actual[2] - expected[2]) < 1e-2, f'Row {i+1}: Expected avg_word_count {expected[2]}, got {actual[2]}'


def normalize_text(value):
    value = unicodedata.normalize('NFKC', str(value)).lower()
    value = ''.join(ch for ch in value if ch.isalnum() or ch.isspace())
    return ' '.join(value.split())


def expected_rows(csv_records, json_records):
    combined = csv_records + json_records
    earliest = {}
    for record in combined:
        normalized = normalize_text(record['text'])
        candidate = dict(record)
        candidate['_normalized'] = normalized
        if normalized not in earliest or candidate['timestamp'] < earliest[normalized]['timestamp']:
            earliest[normalized] = candidate

    grouped = {}
    for record in earliest.values():
        normalized = record['_normalized']
        word_count = 0 if normalized == '' else len(normalized.split(' '))
        grouped.setdefault(record['product_id'], []).append(word_count)

    result = []
    for product_id, counts in grouped.items():
        result.append((product_id, len(counts), sum(counts) / len(counts)))
    result.sort(key=lambda row: (-row[1], row[0]))
    return [['product_id', 'review_count', 'avg_word_count']] + [
        [product_id, str(count), f'{average:.2f}']
        for product_id, count, average in result
    ]


def install_fixture(csv_records, json_records):
    with CSV_INPUT.open('w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['review_id', 'product_id', 'text', 'timestamp'])
        writer.writeheader()
        writer.writerows(csv_records)
    with JSON_INPUT.open('w', encoding='utf-8') as f:
        json.dump(json_records, f, ensure_ascii=False)
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()


def check_dynamic_output(csv_records, json_records):
    actual = read_output()
    expected = expected_rows(csv_records, json_records)
    assert actual == expected, f'Dynamic fixture mismatch. Expected {expected}, got {actual}'


def find_python_scripts():
    scripts = []
    excluded_dirs = {'.git', '.local', '__pycache__', 'site-packages', 'venv', '.venv'}
    for path in HOME.rglob('*'):
        try:
            relative = path.relative_to(HOME)
            if len(relative.parts) > 4 or any(part in excluded_dirs for part in relative.parts[:-1]):
                continue
            if path.is_symlink() or not path.is_file() or path in (CSV_INPUT, JSON_INPUT, OUTPUT):
                continue
            is_candidate = path.suffix.lower() == '.py'
            if not is_candidate and path.stat().st_size <= 1024 * 1024:
                with path.open('rb') as f:
                    first_line = f.readline(256).lower()
                is_candidate = first_line.startswith(b'#!') and b'python' in first_line
            if is_candidate:
                scripts.append(path)
        except (OSError, UnicodeError):
            continue
    return sorted(scripts, key=lambda p: (len(p.relative_to(HOME).parts), str(p)))


def run_script(path):
    completed = subprocess.run(
        ['python3', str(path)],
        cwd=str(HOME),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        text=True,
    )
    assert completed.returncode == 0, (
        f'{path} exited with status {completed.returncode}. stderr: {completed.stderr[-2000:]}'
    )
    assert OUTPUT.is_file(), f'{path} did not generate {OUTPUT}'


def restore_file(path, data):
    path.write_bytes(data)
    os.chmod(path, 0o666)


# Preserve all checks against the required result for the supplied fixture.
check_original_output()
original_csv = CSV_INPUT.read_bytes()
original_json = JSON_INPUT.read_bytes()
original_output = OUTPUT.read_bytes()

nonce = secrets.token_hex(5)
fixtures = [
    (
        [
            {'review_id': 'a1', 'product_id': 'z' + nonce, 'text': 'Ｆｕｌｌ　Ｗｉｄｔｈ!!!', 'timestamp': '2024-02-03T00:00:00Z'},
            {'review_id': 'a2', 'product_id': 'b' + nonce, 'text': 'Привет,   МИР 😊', 'timestamp': '2024-02-01T00:00:00Z'},
            {'review_id': 'a3', 'product_id': 'c' + nonce, 'text': '___!!!', 'timestamp': '2024-02-04T00:00:00Z'},
        ],
        [
            {'review_id': 'a4', 'product_id': 'a' + nonce, 'text': 'full width', 'timestamp': '2024-02-01T00:00:00Z'},
            {'review_id': 'a5', 'product_id': 'x' + nonce, 'text': 'привет мир', 'timestamp': '2024-02-05T00:00:00Z'},
            {'review_id': 'a6', 'product_id': 'c' + nonce, 'text': 'مرحبا، بالعالم', 'timestamp': '2024-02-06T00:00:00Z'},
            {'review_id': 'a7', 'product_id': 'z' + nonce, 'text': 'one two three', 'timestamp': '2024-02-07T00:00:00Z'},
        ],
    ),
    (
        [
            {'review_id': 'b1', 'product_id': 'd' + nonce, 'text': 'Cafe\u0301 -- TEST', 'timestamp': '2025-03-03T00:00:00Z'},
            {'review_id': 'b2', 'product_id': 'a' + nonce, 'text': '中文　文本', 'timestamp': '2025-03-01T00:00:00Z'},
            {'review_id': 'b3', 'product_id': 'd' + nonce, 'text': '!!!😀', 'timestamp': '2025-03-04T00:00:00Z'},
        ],
        [
            {'review_id': 'b4', 'product_id': 'c' + nonce, 'text': 'CAFÉ TEST', 'timestamp': '2025-03-02T00:00:00Z'},
            {'review_id': 'b5', 'product_id': 'x' + nonce, 'text': '中文 文本', 'timestamp': '2025-03-05T00:00:00Z'},
            {'review_id': 'b6', 'product_id': 'b' + nonce, 'text': 'Straße １２３', 'timestamp': '2025-03-06T00:00:00Z'},
            {'review_id': 'b7', 'product_id': 'b' + nonce, 'text': 'second\nline', 'timestamp': '2025-03-07T00:00:00Z'},
        ],
    ),
]

scripts = find_python_scripts()
assert scripts, 'No Python processing script was found under /home/user'
winner = None
last_errors = []

try:
    for script in scripts:
        try:
            for csv_records, json_records in fixtures:
                install_fixture(csv_records, json_records)
                run_script(script)
                check_dynamic_output(csv_records, json_records)

            restore_file(CSV_INPUT, original_csv)
            restore_file(JSON_INPUT, original_json)
            if OUTPUT.exists() or OUTPUT.is_symlink():
                OUTPUT.unlink()
            run_script(script)
            check_original_output()
            winner = script
            break
        except Exception as exc:
            last_errors.append(f'{script}: {exc}')

    assert winner is not None, 'No submitted Python script dynamically processed both inputs. ' + ' | '.join(last_errors[-5:])
finally:
    restore_file(CSV_INPUT, original_csv)
    restore_file(JSON_INPUT, original_json)
    if winner is None:
        restore_file(OUTPUT, original_output)
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
