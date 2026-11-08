#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
from pathlib import Path
import secrets
import subprocess
import sys

REPORT = Path('/home/user/report.txt')
EVENTS = Path('/home/user/events.csv')
ORIGINAL_EXPECTED = 'User U102 had the highest total duration of 450 seconds. Their last recorded browser was Firefox.'


def qualifying_script(path):
    if not path.is_file() or path.is_symlink():
        return False
    try:
        source = path.read_text(encoding='utf-8')
        tree = ast.parse(source)
    except (OSError, UnicodeDecodeError, SyntaxError):
        return False

    # The submitted program must open a file and process it iteratively, rather
    # than loading the complete CSV through common whole-file APIs.
    has_open = any(
        isinstance(n, ast.Call) and (
            isinstance(n.func, ast.Name) and n.func.id == 'open'
            or isinstance(n.func, ast.Attribute) and n.func.attr == 'open'
        )
        for n in ast.walk(tree)
    )
    has_iteration = any(
        isinstance(n, (ast.For, ast.AsyncFor, ast.While, ast.comprehension))
        for n in ast.walk(tree)
    )
    forbidden_bulk_calls = {'read', 'readlines', 'read_text', 'read_bytes'}
    uses_bulk_read = any(
        isinstance(n, ast.Call)
        and isinstance(n.func, ast.Attribute)
        and n.func.attr in forbidden_bulk_calls
        for n in ast.walk(tree)
    )

    re_modules = set()
    re_functions = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 're':
                    re_modules.add(alias.asname or 're')
        elif isinstance(node, ast.ImportFrom) and node.module == 're':
            for alias in node.names:
                if alias.name in {'search', 'match', 'fullmatch', 'findall', 'finditer', 'compile'}:
                    re_functions.add(alias.asname or alias.name)

    regex_calls = {'search', 'match', 'fullmatch', 'findall', 'finditer', 'compile'}
    uses_regex = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in re_functions:
            uses_regex = True
        elif (
            isinstance(node.func, ast.Attribute)
            and node.func.attr in regex_calls
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id in re_modules
        ):
            uses_regex = True

    lower_source = source.lower()
    mentions_fields = 'browser' in lower_source and 'duration' in lower_source
    return has_open and has_iteration and not uses_bulk_read and uses_regex and mentions_fields


def find_scripts():
    ignored = {'.local', '.cache', 'venv', '.venv', 'site-packages', '__pycache__'}
    scripts = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in ignored]
        for name in files:
            if name.endswith('.py'):
                path = Path(root) / name
                if qualifying_script(path):
                    scripts.append(path)
    return scripts


def make_challenge():
    users = ['U' + secrets.token_hex(4).upper() for _ in range(3)]
    browsers = ['B' + secrets.token_hex(5) for _ in range(6)]
    d1 = 40 + secrets.randbelow(20)
    d2 = 120 + secrets.randbelow(20)
    d3 = 210 + secrets.randbelow(20)
    d4 = 250 + secrets.randbelow(20)

    # Each row stores semantic values separately so the expected answer is
    # derived independently of the submitted program.
    rows = [
        (users[0], browsers[0], d1, 'bad \\u02Z unicode'),
        (users[1], browsers[1], d2, 'bad \\u001 unicode'),
        (users[2], browsers[2], d4, 'bad \\u00H unicode'),
        (users[0], browsers[3], None, 'duration omitted \\u9ZZ'),
        (users[1], browsers[4], d3, 'bad \\u12G unicode'),
        (users[1], browsers[5], None, 'duration omitted \\u99Z'),
    ]

    totals = {}
    last_browser = {}
    for user_id, browser, duration, _ in rows:
        totals[user_id] = totals.get(user_id, 0) + (30 if duration is None else duration)
        last_browser[user_id] = browser
    winner = max(totals, key=totals.get)
    expected = (
        f'User {winner} had the highest total duration of {totals[winner]} seconds. '
        f'Their last recorded browser was {last_browser[winner]}.'
    )

    with EVENTS.open('w', encoding='utf-8', newline='') as handle:
        writer = csv.writer(handle)
        writer.writerow(['timestamp', 'user_id', 'event_type', 'payload'])
        for index, (user_id, browser, duration, meta) in enumerate(rows):
            fields = [f'"browser": "{browser}"']
            if duration is not None:
                fields.append(f'"duration": {duration}')
            fields.append(f'"meta": "{meta}"')
            payload = '{' + ', '.join(fields) + '}'
            writer.writerow([f'2026-01-01T00:00:{index:02d}Z', user_id, 'event', payload])
    return expected


def test_original_report_and_executable_streaming_script():
    # Preserve the original verifier's assertions on the agent-generated report.
    assert REPORT.exists(), f'The file {REPORT} was not created.'
    assert REPORT.is_file(), f'{REPORT} is not a valid file.'
    actual = REPORT.read_text(encoding='utf-8').strip()
    assert actual == ORIGINAL_EXPECTED, (
        f'The content of {REPORT} is incorrect.\n'
        f'Expected: {ORIGINAL_EXPECTED!r}\nGot: {actual!r}'
    )

    scripts = find_scripts()
    assert scripts, 'No Python script using iterative file processing and regular-expression extraction was found.'

    expected = make_challenge()
    failures = []
    for script in scripts:
        REPORT.unlink(missing_ok=True)
        # Restore the same hidden challenge before every candidate execution.
        expected = make_challenge()
        try:
            result = subprocess.run(
                [sys.executable, str(script)],
                cwd='/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
        except subprocess.TimeoutExpired:
            failures.append(f'{script}: timed out')
            continue

        if result.returncode != 0:
            failures.append(f'{script}: exited with status {result.returncode}')
            continue
        if not REPORT.is_file():
            failures.append(f'{script}: did not create report.txt')
            continue
        produced = REPORT.read_text(encoding='utf-8').strip()
        if produced == expected:
            return
        failures.append(f'{script}: incorrect report for verifier-generated CSV')

    raise AssertionError('No submitted script correctly processed the verifier-generated malformed CSV. ' + '; '.join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
