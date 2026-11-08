#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest

INPUT = Path('/home/user/activity_wide.csv')
OUTPUT = Path('/home/user/token_counts.json')
APPS = ['AppAlpha', 'AppBeta', 'AppGamma']
TIMESTAMPS = [f'2023-10-01T{hour:02d}:{minute:02d}:00Z'
              for hour, minute in [(10,0),(10,15),(10,30),(10,45),(11,0),(11,15),(11,30),(11,45)]]

ORIGINAL_CSV = '''Timestamp,AppAlpha,AppBeta,AppGamma
2023-10-01T10:00:00Z,Login-Success_US,ERR_500-Timeout,
2023-10-01T10:15:00Z,,Login:Success_EU,Sync-Complete
2023-10-01T10:45:00Z,ERR:404_Not_Found,,Data_Load_100%
2023-10-01T11:00:00Z,Login-Success_US,ERR_500-Timeout,Sync-Complete
2023-10-01T11:30:00Z,,,
2023-10-01T11:45:00Z,Logout_User_123,Logout_User_456,Data_Load_100%
'''

EXPECTED_ORIGINAL = {
    'AppAlpha': {
        'err 404 not found': 1,
        'login success us': 2,
        'logout user 123': 1,
        'no_action': 4
    },
    'AppBeta': {
        'err 500 timeout': 2,
        'login success eu': 1,
        'logout user 456': 1,
        'no_action': 4
    },
    'AppGamma': {
        'data load 100': 2,
        'no_action': 4,
        'sync complete': 2
    }
}


def find_go_programs():
    groups = {}
    for path in Path('/home/user').rglob('*.go'):
        if path.name.endswith('_test.go'):
            continue
        if '/go/pkg/mod/' in str(path) or '/.cache/' in str(path):
            continue
        try:
            text = path.read_text(errors='ignore')
        except OSError:
            continue
        if re.search(r'(?m)^\s*package\s+main\b', text) and re.search(r'\bfunc\s+main\s*\(', text):
            groups[path.parent] = sorted(
                p for p in path.parent.glob('*.go') if not p.name.endswith('_test.go')
            )

    programs = []
    for directory, files in sorted(groups.items(), key=lambda item: str(item[0])):
        current = directory
        has_module = False
        while current == Path('/home/user') or Path('/home/user') in current.parents:
            if (current / 'go.mod').is_file():
                has_module = True
                break
            if current == Path('/home/user'):
                break
            current = current.parent
        command = ['go', 'run', '.'] if has_module else ['go', 'run', *map(str, files)]
        programs.append((directory, command))
    return programs


def execute(directory, command, csv_text):
    INPUT.write_text(csv_text)
    try:
        OUTPUT.unlink()
    except FileNotFoundError:
        pass
    return subprocess.run(
        command,
        cwd=directory,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        env=os.environ.copy(),
    )


def load_output():
    assert OUTPUT.is_file(), f'The required output file {OUTPUT} is missing. Did your Go program run and generate it?'
    try:
        with OUTPUT.open() as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'The file {OUTPUT} does not contain valid JSON.')


def expected_from_csv(csv_text):
    rows = {row['Timestamp']: row for row in csv.DictReader(io.StringIO(csv_text))}
    result = {app: {} for app in APPS}
    for timestamp in TIMESTAMPS:
        row = rows.get(timestamp)
        for app in APPS:
            raw = 'NONE' if row is None or row.get(app, '') == '' else row[app]
            token = re.sub(r'[^a-z0-9]', ' ', raw.lower())
            token = ' '.join(token.split())
            if not token or token == 'none':
                token = 'no_action'
            result[app][token] = result[app].get(token, 0) + 1
    return result


def make_dynamic_csv():
    a = secrets.token_hex(5)
    b = secrets.token_hex(5)
    c = secrets.token_hex(5)
    rows = [
        ['2023-10-01T10:00:00Z', f'{a.upper()}__Start!!', f'{b}-Run', ''],
        ['2023-10-01T10:15:00Z', f'{c}:Step', 'NONE', f'{a}_Sync'],
        # 10:30 is deliberately missing.
        ['2023-10-01T10:45:00Z', '', f'{b}-Run', '...'],
        ['2023-10-01T11:00:00Z', f'{a.upper()}__Start!!', '', f'{a}_Sync'],
        # 11:15 is deliberately missing.
        ['2023-10-01T11:30:00Z', '___', f'{c}++Done', 'Value:100%'],
        ['2023-10-01T11:45:00Z', 'NONE', f'{c}++Done', 'Value:100%'],
    ]
    out = io.StringIO()
    writer = csv.writer(out, lineterminator='\n')
    writer.writerow(['Timestamp', *APPS])
    writer.writerows(rows)
    return out.getvalue()


def test_go_etl_program_and_token_counts():
    programs = find_go_programs()
    assert programs, 'No runnable Go program with package main and func main was found under /home/user.'

    selected = None
    failures = []
    for directory, command in programs:
        try:
            proc = execute(directory, command, ORIGINAL_CSV)
            if proc.returncode != 0:
                failures.append(f'{directory}: {proc.stderr}')
                continue
            data = load_output()
            if data == EXPECTED_ORIGINAL:
                selected = (directory, command)
                break
            failures.append(f'{directory}: produced incorrect original aggregation')
        except (AssertionError, subprocess.TimeoutExpired) as exc:
            failures.append(f'{directory}: {exc}')

    assert selected is not None, 'No Go program generated the required original output when executed. ' + ' | '.join(failures)

    # Retain the original verifier's existence and exact-content assertions.
    assert OUTPUT.is_file(), f'The required output file {OUTPUT} is missing.'
    data = load_output()
    assert 'AppAlpha' in data, "Missing 'AppAlpha' in the output JSON."
    assert 'AppBeta' in data, "Missing 'AppBeta' in the output JSON."
    assert 'AppGamma' in data, "Missing 'AppGamma' in the output JSON."
    assert data['AppAlpha'] == EXPECTED_ORIGINAL['AppAlpha']
    assert data['AppBeta'] == EXPECTED_ORIGINAL['AppBeta']
    assert data['AppGamma'] == EXPECTED_ORIGINAL['AppGamma']
    assert data == EXPECTED_ORIGINAL, 'The overall JSON output does not match the expected aggregation counts.'

    # Exercise the submitted program on fresh, unpredictable input and derive
    # the expected aggregation independently from that input.
    dynamic_csv = make_dynamic_csv()
    expected_dynamic = expected_from_csv(dynamic_csv)
    directory, command = selected
    proc = execute(directory, command, dynamic_csv)
    assert proc.returncode == 0, f'Go program failed on verification input: {proc.stderr}'
    dynamic_data = load_output()
    assert dynamic_data == expected_dynamic, f'Dynamic ETL result is incorrect. Expected {expected_dynamic}, got {dynamic_data}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
