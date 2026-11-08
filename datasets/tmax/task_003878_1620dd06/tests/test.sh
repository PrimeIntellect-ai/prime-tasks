#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import sqlite3
import stat
import subprocess
from datetime import datetime, timezone
from pathlib import Path

SCRIPT = Path('/home/user/process_events.sh')
DB = Path('/home/user/analytics.db')
REPORT = Path('/home/user/report.html')
RAW = Path('/home/user/raw_events.csv')
TEMPLATE = Path('/home/user/template.html')


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f'Script {SCRIPT} does not exist.'
    assert os.access(SCRIPT, os.X_OK), f'Script {SCRIPT} is not executable.'
    assert stat.S_ISREGULAR(os.lstat(SCRIPT).st_mode), f'{SCRIPT} must be a regular file.'
    first_line = SCRIPT.read_text(errors='replace').splitlines()[0]
    assert first_line.startswith('#!') and 'bash' in first_line, 'The executable must be a Bash script.'


def test_database_exists():
    assert os.path.isfile(DB), f'Database {DB} does not exist.'


def test_database_content():
    assert os.path.isfile(DB), f'Database {DB} does not exist.'

    conn = sqlite3.connect(DB)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='events';")
    assert cursor.fetchone() is not None, "Table 'events' does not exist in the database."

    cursor.execute('SELECT id, timestamp, email, action, amount FROM events ORDER BY id ASC;')
    rows = cursor.fetchall()
    expected_rows = [
        (1, '2023-01-01 00:00:00', '***@example.com', 'LOGIN', 0),
        (2, '2023-01-01 01:30:00', '***@domain.com', 'PURCHASE', 50),
        (3, '2023-01-01 02:00:00', '***@test.org', 'LOGOUT', 0),
        (4, '2023-01-02 10:15:00', '***@example.com', 'PURCHASE', 120),
        (5, '2023-01-03 10:00:00', '***@hacker.net', 'PURCHASE', 300),
    ]

    assert len(rows) == len(expected_rows), f'Expected {len(expected_rows)} rows, but got {len(rows)}.'
    for i, (row, expected) in enumerate(zip(rows, expected_rows)):
        assert row == expected, f'Row {i + 1} mismatch. Expected {expected}, got {row}.'
    conn.close()


def test_report_html_content():
    assert os.path.isfile(REPORT), f'Report file {REPORT} does not exist.'
    content = REPORT.read_text().strip()
    expected_content = '''<html>
<body>
<h1>Daily Report</h1>
<p>Total Events: 5</p>
<p>Unique Domains: 4</p>
<p>Total Revenue: $470</p>
</body>
</html>'''

    def normalize(text):
        return '\n'.join(line.strip() for line in text.strip().splitlines() if line.strip())

    assert normalize(content) == normalize(expected_content), 'The content of report.html does not match the expected output.'


def test_script_processes_a_fresh_fixture_end_to_end():
    token = secrets.token_hex(6)
    domains = [f'alpha-{token}.test', f'beta-{token}.test', f'alpha-{token}.test', f'gamma-{token}.test']
    emails = [
        f'first.{token}@{domains[0]}',
        f'second-{token}@{domains[1]}',
        f'third_{token}@{domains[2]}',
        f'fourth.{token}@{domains[3]}',
    ]
    ids = [41, 7, 93, 18]
    amounts = [13, 206, 0, 71]
    timestamps = [
        str(int(datetime(2024, 2, 29, 23, 5, 7, tzinfo=timezone.utc).timestamp())),
        '2025-07-08T09:10:11Z',
        str(int(datetime(2022, 11, 3, 4, 5, 6, tzinfo=timezone.utc).timestamp())),
        '2026-01-02T03:04:05Z',
    ]
    expected_times = [
        '2024-02-29 23:05:07',
        '2025-07-08 09:10:11',
        '2022-11-03 04:05:06',
        '2026-01-02 03:04:05',
    ]
    actions = ['OPEN', 'PURCHASE', 'CLOSE', 'REFUND']

    lines = ['id,timestamp,email,action,amount']
    for row in zip(ids, timestamps, emails, actions, amounts):
        lines.append(','.join(map(str, row)))
    RAW.write_text('\n'.join(lines) + '\n')

    marker = f'dynamic-{secrets.token_hex(5)}'
    template_text = f'''<html>
<body data-marker="{marker}">
<section>Total={{TOTAL_EVENTS}}</section>
<section>Domains={{UNIQUE_DOMAINS}}</section>
<section>Amount={{TOTAL_AMOUNT}}</section>
</body>
</html>
'''
    TEMPLATE.write_text(template_text)

    for path in (DB, REPORT):
        if path.exists() or path.is_symlink():
            path.unlink()

    env = os.environ.copy()
    env['TZ'] = 'America/Los_Angeles'
    result = subprocess.run(
        [str(SCRIPT)], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f'Script failed with exit {result.returncode}. stdout={result.stdout!r} stderr={result.stderr!r}'
    assert DB.is_file(), 'The script did not create analytics.db for the fresh input.'
    assert REPORT.is_file(), 'The script did not create report.html for the fresh input.'

    conn = sqlite3.connect(DB)
    try:
        schema = conn.execute("PRAGMA table_info(events)").fetchall()
        assert [(r[1], r[2].upper()) for r in schema] == [
            ('id', 'INTEGER'), ('timestamp', 'TEXT'), ('email', 'TEXT'),
            ('action', 'TEXT'), ('amount', 'INTEGER')
        ], f'Unexpected events schema: {schema!r}'

        rows = conn.execute(
            'SELECT id, timestamp, email, action, amount FROM events ORDER BY id'
        ).fetchall()
    finally:
        conn.close()

    expected_rows = sorted([
        (ids[i], expected_times[i], f'***@{domains[i]}', actions[i], amounts[i])
        for i in range(len(ids))
    ])
    assert rows == expected_rows, f'Fresh-fixture database rows were incorrect: {rows!r}'

    expected_report = (template_text
        .replace('{{TOTAL_EVENTS}}', str(len(ids)))
        .replace('{{UNIQUE_DOMAINS}}', str(len(set(domains))))
        .replace('{{TOTAL_AMOUNT}}', str(sum(amounts))))
    assert REPORT.read_text() == expected_report, 'The fresh-fixture report was not generated from the supplied template and computed metrics.'

    # The source CSV must remain, but no other leftover file may retain an unmasked
    # address from this run.
    leaked = []
    for root in ('/home/user', '/tmp'):
        for dirpath, _, filenames in os.walk(root):
            for filename in filenames:
                path = Path(dirpath) / filename
                if path == RAW or path == Path('/tmp/test_final_state.py'):
                    continue
                try:
                    if not path.is_file() or path.stat().st_size > 20_000_000:
                        continue
                    data = path.read_bytes()
                except OSError:
                    continue
                if any(email.encode() in data for email in emails):
                    leaked.append(str(path))
    assert not leaked, f'Unmasked intermediate data was left on disk: {leaked}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
