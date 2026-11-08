#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import re
import secrets
import shutil
import string
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

import pytest

SCRIPT_PATH = Path('/home/user/process_reviews.py')
JSON_PATH = Path('/home/user/product_frequencies.json')
REVIEWS_PATH = Path('/home/user/data/reviews')


def test_json_file_exists():
    """Check if the product_frequencies.json file was created."""
    assert JSON_PATH.is_file(), f"The file {JSON_PATH} does not exist."


def test_json_content_correct():
    """Check if the content of product_frequencies.json matches the expected frequencies."""
    assert JSON_PATH.is_file(), f"The file {JSON_PATH} does not exist."

    with JSON_PATH.open('r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {JSON_PATH} as JSON: {e}")

    expected = {
        "AB-12345": 4,
        "XYZ-98765": 3,
        "ZZ-0000": 1,
        "RU-55555": 1
    }
    assert data == expected, f"JSON content does not match expected frequencies. Expected {expected}, got {data}"


def test_script_exists():
    """Check if the python script was created."""
    assert SCRIPT_PATH.is_file(), f"The script {SCRIPT_PATH} does not exist."


def test_script_uses_parallel_processing():
    source = SCRIPT_PATH.read_text(encoding='utf-8')
    assert source.strip(), 'process_reviews.py is empty.'
    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        pytest.fail(f'process_reviews.py is not valid Python: {e}')

    constructors = {
        'Pool', 'Process', 'ProcessPoolExecutor', 'ThreadPoolExecutor'
    }
    imported_parallel = False
    imported_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'multiprocessing' or alias.name.startswith('concurrent.futures'):
                    imported_parallel = True
        elif isinstance(node, ast.ImportFrom):
            if node.module and (node.module == 'multiprocessing' or node.module.startswith('concurrent.futures')):
                imported_parallel = True
                for alias in node.names:
                    if alias.name in constructors:
                        imported_names.add(alias.asname or alias.name)

    called_parallel = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in imported_names:
            called_parallel = True
        elif isinstance(node.func, ast.Attribute) and node.func.attr in constructors:
            called_parallel = True

    assert imported_parallel and called_parallel, (
        'The script must actually construct multiprocessing or concurrent.futures workers.'
    )


def _random_code(letter_count, digit_count):
    letters = ''.join(secrets.choice(string.ascii_uppercase) for _ in range(letter_count))
    digits = ''.join(secrets.choice(string.digits) for _ in range(digit_count))
    return f'{letters}-{digits}'


def test_script_processes_fresh_multiencoding_csvs():
    codes = set()
    while len(codes) < 4:
        codes.add(_random_code(secrets.choice((2, 3)), secrets.choice((4, 5))))
    a, b, c, d = list(codes)

    fixtures = [
        ('utf8.csv', 'utf-8', [
            ('1', f'Excellent {a}; I also bought {b}.'),
            ('2', f'{a} appears twice: {a}. Invalid A-1234 and ABCD-12345.'),
        ]),
        ('latin.csv', 'latin-1', [
            ('3', f'Café review for {c}.'),
            ('4', f'No valid code here; {d.lower()} is lowercase.'),
        ]),
        ('japanese.csv', 'shift_jis', [
            ('5', f'製品 {b} は良いです。'),
            ('6', f'比較: {d} and {d}.'),
        ]),
        ('russian.csv', 'windows-1251', [
            ('7', f'Отличный товар {a}.'),
            ('8', f'Также рекомендую {c} и {d}.'),
        ]),
    ]

    expected = Counter()
    pattern = re.compile(r'\b[A-Z]{2,3}-\d{4,5}\b')
    for _, _, rows in fixtures:
        for _, text in rows:
            expected.update(pattern.findall(text))

    temp_root = Path(tempfile.mkdtemp(prefix='review-verifier-'))
    backup_reviews = temp_root / 'original_reviews'
    output_existed = JSON_PATH.exists()
    original_output = JSON_PATH.read_bytes() if output_existed else None

    try:
        if REVIEWS_PATH.exists() or REVIEWS_PATH.is_symlink():
            shutil.move(str(REVIEWS_PATH), str(backup_reviews))
        REVIEWS_PATH.mkdir(parents=True)

        for filename, encoding, rows in fixtures:
            with (REVIEWS_PATH / filename).open('w', encoding=encoding, newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['review_id', 'review_text'])
                writer.writerows(rows)

        if JSON_PATH.exists():
            JSON_PATH.unlink()

        result = subprocess.run(
            [sys.executable, str(SCRIPT_PATH)],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f'process_reviews.py failed on fresh encoded CSVs.\n'
            f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
        )
        assert JSON_PATH.is_file(), 'Running process_reviews.py did not create product_frequencies.json.'
        try:
            with JSON_PATH.open('r', encoding='utf-8') as f:
                actual = json.load(f)
        except (UnicodeDecodeError, json.JSONDecodeError) as e:
            pytest.fail(f'Generated output is not valid UTF-8 JSON: {e}')

        assert actual == dict(expected), (
            f'Fresh-input frequencies are wrong. Expected {dict(expected)}, got {actual}'
        )
        assert all(isinstance(v, int) and not isinstance(v, bool) for v in actual.values())
    finally:
        if REVIEWS_PATH.exists() or REVIEWS_PATH.is_symlink():
            if REVIEWS_PATH.is_dir() and not REVIEWS_PATH.is_symlink():
                shutil.rmtree(REVIEWS_PATH)
            else:
                REVIEWS_PATH.unlink()
        if backup_reviews.exists() or backup_reviews.is_symlink():
            shutil.move(str(backup_reviews), str(REVIEWS_PATH))
        if output_existed:
            JSON_PATH.write_bytes(original_output)
        elif JSON_PATH.exists():
            JSON_PATH.unlink()
        shutil.rmtree(temp_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
