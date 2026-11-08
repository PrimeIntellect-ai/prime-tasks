#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import sqlite3
import subprocess
from collections import Counter
from pathlib import Path

DB_PATH = Path('/home/user/report.db')
TXT_PATH = Path('/home/user/top_threats.txt')
CSV_PATH = Path('/home/user/logs/server_logs.csv')
JSON_PATH = Path('/home/user/logs/auth_logs.json')


def assert_original_outputs():
    assert DB_PATH.exists(), f'Database file {DB_PATH} is missing.'
    assert DB_PATH.is_file(), f'Path {DB_PATH} is not a file.'

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='suspicious_ips';")
        assert cursor.fetchone() is not None, "Table 'suspicious_ips' does not exist in the database."

        cursor.execute('PRAGMA table_info(suspicious_ips);')
        columns = {row[1]: row[2].upper() for row in cursor.fetchall()}
        assert 'ip' in columns, "Column 'ip' is missing from 'suspicious_ips'."
        assert 'attempts' in columns, "Column 'attempts' is missing from 'suspicious_ips'."

        cursor.execute('SELECT ip, attempts FROM suspicious_ips ORDER BY attempts DESC, ip ASC;')
        rows = cursor.fetchall()
        expected_data = [
            ('198.51.100.0', 4),
            ('192.0.2.0', 2),
            ('203.0.113.0', 1),
        ]
        assert rows == expected_data, f'Database content is incorrect. Expected {expected_data}, got {rows}.'

        cursor.execute('SELECT SUM(attempts) FROM suspicious_ips;')
        total_attempts = cursor.fetchone()[0]
        assert total_attempts == 7, f'Expected 7 total attempts, got {total_attempts}.'
    finally:
        conn.close()

    assert TXT_PATH.exists(), f'File {TXT_PATH} is missing.'
    assert TXT_PATH.is_file(), f'Path {TXT_PATH} is not a file.'
    lines = [line.strip() for line in TXT_PATH.read_text().splitlines() if line.strip()]
    expected_lines = [
        '198.51.100.0,4',
        '192.0.2.0,2',
        '203.0.113.0,1',
    ]
    assert lines == expected_lines, f'File content of {TXT_PATH} is incorrect. Expected {expected_lines}, got {lines}.'


def find_bash_scripts():
    scripts = []
    for path in Path('/home/user').rglob('*'):
        if not path.is_file() or path in (DB_PATH, TXT_PATH, CSV_PATH, JSON_PATH):
            continue
        is_script = path.suffix == '.sh'
        if not is_script:
            try:
                first_line = path.open('rb').readline(256).decode('utf-8', errors='ignore')
                is_script = first_line.startswith('#!') and 'bash' in first_line
            except OSError:
                is_script = False
        if is_script:
            scripts.append(path)
    return sorted(scripts)


def make_fixture():
    first_octets = [11, 37, 83, 149]
    prefixes = [f'{first}.{secrets.randbelow(250) + 1}.{secrets.randbelow(250) + 1}' for first in first_octets]
    a, b, c, d = prefixes

    csv_rows = [
        ['timestamp', 'ip_address', 'status_code', 'endpoint'],
        ['2026-01-01T00:00:00Z', f'{a}.17', '400', '/a'],
        ['2026-01-01T00:00:01Z', f'{a}.231', '599', '/b'],
        ['2026-01-01T00:00:02Z', f'{b}.44', '401', '/c'],
        ['2026-01-01T00:00:03Z', f'{c}.91', '500', '/d'],
        ['2026-01-01T00:00:04Z', f'{d}.7', '418', '/e'],
        ['2026-01-01T00:00:05Z', f'{a}.88', '399', '/not-suspicious'],
    ]
    auth_rows = [
        {'time': '00:01', 'src_ip': f'{a}.203', 'event': 'login', 'status': 'failed'},
        {'time': '00:02', 'src_ip': f'{b}.12', 'event': 'login', 'status': 'failed'},
        {'time': '00:03', 'src_ip': f'{c}.222', 'event': 'login', 'status': 'failed'},
        {'time': '00:04', 'src_ip': f'{d}.19', 'event': 'login', 'status': 'success'},
        {'time': '00:05', 'src_ip': f'{a}.204', 'event': 'login', 'status': 'Failed'},
    ]
    return csv_rows, auth_rows


def write_fixture(csv_rows, auth_rows):
    with CSV_PATH.open('w', newline='') as handle:
        csv.writer(handle, lineterminator='\n').writerows(csv_rows)
    JSON_PATH.write_text(json.dumps(auth_rows, indent=2) + '\n')


def derive_expected_from_logs():
    counts = Counter()
    with CSV_PATH.open(newline='') as handle:
        for row in csv.DictReader(handle):
            if int(row['status_code']) >= 400:
                counts[row['ip_address'].rsplit('.', 1)[0] + '.0'] += 1
    for row in json.loads(JSON_PATH.read_text()):
        if row['status'] == 'failed':
            counts[row['src_ip'].rsplit('.', 1)[0] + '.0'] += 1
    all_rows = sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    return all_rows, all_rows[:3]


def assert_dynamic_outputs(expected_rows, expected_top):
    assert DB_PATH.exists() and DB_PATH.is_file(), 'The script did not recreate /home/user/report.db.'
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='suspicious_ips';")
        assert cursor.fetchone() is not None, "Table 'suspicious_ips' was not recreated."
        cursor.execute('PRAGMA table_info(suspicious_ips);')
        columns = {row[1]: row[2].upper() for row in cursor.fetchall()}
        assert 'ip' in columns, "Column 'ip' is missing after regeneration."
        assert 'attempts' in columns, "Column 'attempts' is missing after regeneration."
        cursor.execute('SELECT ip, attempts FROM suspicious_ips ORDER BY attempts DESC, ip ASC;')
        actual_rows = cursor.fetchall()
        assert actual_rows == expected_rows, f'Regenerated database is incorrect. Expected {expected_rows}, got {actual_rows}.'
        cursor.execute('SELECT SUM(attempts) FROM suspicious_ips;')
        assert cursor.fetchone()[0] == sum(count for _, count in expected_rows)
    finally:
        conn.close()

    assert TXT_PATH.exists() and TXT_PATH.is_file(), 'The script did not recreate /home/user/top_threats.txt.'
    actual_lines = [line.strip() for line in TXT_PATH.read_text().splitlines() if line.strip()]
    expected_lines = [f'{ip},{count}' for ip, count in expected_top]
    assert actual_lines == expected_lines, f'Regenerated top threats are incorrect. Expected {expected_lines}, got {actual_lines}.'


def test_final_state_and_script_regeneration():
    # Preserve all checks against the originally supplied fixture.
    assert_original_outputs()

    scripts = find_bash_scripts()
    assert scripts, 'No Bash script was found under /home/user.'

    original_csv = CSV_PATH.read_bytes()
    original_json = JSON_PATH.read_bytes()
    csv_rows, auth_rows = make_fixture()
    failures = []
    succeeded = False

    try:
        for script in scripts:
            write_fixture(csv_rows, auth_rows)
            expected_rows, expected_top = derive_expected_from_logs()
            DB_PATH.unlink(missing_ok=True)
            TXT_PATH.unlink(missing_ok=True)

            env = os.environ.copy()
            env['HOME'] = '/home/user'
            try:
                result = subprocess.run(
                    ['bash', str(script)],
                    cwd='/home/user',
                    env=env,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=30,
                )
                assert result.returncode == 0, f'exited with {result.returncode}: {result.stderr[-1000:]}'
                assert_dynamic_outputs(expected_rows, expected_top)
                succeeded = True
                break
            except Exception as exc:
                failures.append(f'{script}: {exc}')

        assert succeeded, 'No submitted Bash script regenerated correct artifacts from changed logs. ' + ' | '.join(failures)
    finally:
        CSV_PATH.write_bytes(original_csv)
        JSON_PATH.write_bytes(original_json)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
