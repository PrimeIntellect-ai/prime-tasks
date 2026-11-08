#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
import unicodedata
from pathlib import Path

HOME = Path('/home/user')


def test_process_go_exists():
    file_path = '/home/user/process.go'
    assert os.path.isfile(file_path), f'File {file_path} is missing. The Go script was not created.'


def test_makefile_exists():
    file_path = '/home/user/Makefile'
    assert os.path.isfile(file_path), f'File {file_path} is missing. The Makefile was not generated.'


def _assert_original_result(lang, expected):
    file_path = f'/home/user/result_{lang}.txt'
    assert os.path.isfile(file_path), f"File {file_path} is missing. Did 'make' run successfully?"
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()
    assert content == expected, f"Expected '{expected}' in {file_path}, but got '{content}'."


def test_result_en():
    _assert_original_result('en', '102')


def test_result_ja():
    _assert_original_result('ja', '202')


def test_result_ar():
    _assert_original_result('ar', '302')


def test_result_ru():
    _assert_original_result('ru', '402')


def _expected_from_csv(path):
    winners = {}
    with open(path, newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            digit_sum = 0
            for char in row['text']:
                if unicodedata.category(char) == 'Nd':
                    digit_sum += unicodedata.decimal(char)
            item = (digit_sum, int(row['id']))
            previous = winners.get(row['lang'])
            if previous is None or item[0] > previous[0] or (item[0] == previous[0] and item[1] < previous[1]):
                winners[row['lang']] = item
    return {lang: str(item[1]) for lang, item in winners.items()}


def _target_details(makefile_text, target):
    match = re.search(r'^' + re.escape(target) + r'\s*:(.*)$', makefile_text, re.MULTILINE)
    assert match is not None, f'Makefile is missing target {target}'
    tail = match.group(1)
    prerequisites = tail.split(';', 1)[0].split()

    inline_command = tail.split(';', 1)[1].strip() if ';' in tail else ''
    following = makefile_text[match.end():].splitlines()
    recipes = []
    for line in following:
        if line.startswith('\t'):
            if line[1:].strip():
                recipes.append(line[1:].strip())
        elif not line.strip() or line.lstrip().startswith('#'):
            continue
        else:
            break
    commands = ([inline_command] if inline_command else []) + recipes
    return prerequisites, commands


def test_program_generates_and_make_executes_dynamic_pipeline():
    token = secrets.token_hex(4)
    languages = [f'v{token}a', f'v{token}b', f'v{token}c', f'v{token}d']
    digit_pairs = [
        ('９９', '٩٨١'),
        ('٩٩', '९६३'),
        ('৯৯', '８７３'),
        ('99', '৯৫৪'),
    ]

    rows = []
    for index, (lang, pair) in enumerate(zip(languages, digit_pairs)):
        base = 10000 + index * 1000 + secrets.randbelow(500)
        rows.extend([
            {'id': str(base + 40), 'lang': lang, 'text': 'low value, ٥'},
            {'id': str(base + 20), 'lang': lang, 'text': f'first maximum, {pair[0]}'},
            {'id': str(base + 3), 'lang': lang, 'text': f'tied maximum, {pair[1]}'},
        ])

    preserved_paths = [HOME / 'locales.csv', HOME / 'Makefile'] + [HOME / f'result_{lang}.txt' for lang in ('en', 'ja', 'ar', 'ru')]
    backups = {path: path.read_bytes() for path in preserved_paths if path.exists()}
    dynamic_results = [HOME / f'result_{lang}.txt' for lang in languages]

    try:
        with open(HOME / 'locales.csv', 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=['id', 'lang', 'text'])
            writer.writeheader()
            writer.writerows(rows)

        expected = _expected_from_csv(HOME / 'locales.csv')
        assert set(expected) == set(languages)

        (HOME / 'Makefile').unlink(missing_ok=True)
        for path in dynamic_results:
            path.unlink(missing_ok=True)

        run = subprocess.run(
            ['go', 'run', '/home/user/process.go'], cwd=HOME,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60
        )
        assert run.returncode == 0, f'Go program failed:\n{run.stdout}'
        assert (HOME / 'Makefile').is_file(), 'Running process.go did not generate /home/user/Makefile'

        makefile_text = (HOME / 'Makefile').read_text(encoding='utf-8')
        all_prerequisites, _ = _target_details(makefile_text, 'all')
        required_targets = {f'process_{lang}' for lang in languages}
        assert required_targets.issubset(set(all_prerequisites)), 'The all target does not depend on every language target'

        for lang in languages:
            _, commands = _target_details(makefile_text, f'process_{lang}')
            assert len(commands) == 1, f'process_{lang} must contain exactly one command'

        for path in dynamic_results:
            path.unlink(missing_ok=True)
        made = subprocess.run(
            ['make', '-f', '/home/user/Makefile', 'all'], cwd=HOME,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30
        )
        assert made.returncode == 0, f'make all failed:\n{made.stdout}'
        for lang in languages:
            path = HOME / f'result_{lang}.txt'
            assert path.is_file(), f'make all did not create {path}'
            assert path.read_text(encoding='utf-8').strip() == expected[lang]

        for lang in languages:
            path = HOME / f'result_{lang}.txt'
            path.unlink(missing_ok=True)
            made = subprocess.run(
                ['make', '-f', '/home/user/Makefile', f'process_{lang}'], cwd=HOME,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30
            )
            assert made.returncode == 0, f'Language target process_{lang} failed:\n{made.stdout}'
            assert path.is_file(), f'process_{lang} did not create {path}'
            assert path.read_text(encoding='utf-8').strip() == expected[lang]
    finally:
        for path in dynamic_results:
            path.unlink(missing_ok=True)
        for path, data in backups.items():
            path.write_bytes(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
