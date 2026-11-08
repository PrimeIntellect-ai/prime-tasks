#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import sqlite3
import stat
import subprocess

SCRIPT = '/home/user/validate_backups.sh'
DB = '/home/user/backups.db'
LOGS = '/home/user/backup_logs.json'
OUTPUT = '/home/user/final_size.txt'


def run_script(expected):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        [SCRIPT],
        cwd='/home/user',
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}. stderr: {result.stderr!r}"
    )
    assert result.stdout.strip() == str(expected), (
        f"Script must output only {expected}, but stdout was {result.stdout!r}"
    )
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist. Did your script create it?"
    with open(OUTPUT, 'r') as f:
        content = f.read().strip()
    assert content == str(expected), (
        f"Expected the final size to be exactly {expected}, but found {content!r} in {OUTPUT}."
    )


def reference_total():
    with sqlite3.connect(DB) as conn:
        ids = {
            row[0] for row in conn.execute(
                """
                SELECT DISTINCT b.id
                FROM backups AS b
                JOIN servers AS s ON s.server_name = b.server_name
                JOIN backup_metadata AS m ON m.backup_id = b.id
                WHERE m.status = 'SUCCESS' AND s.region = 'us-east-1'
                """
            )
        }
    with open(LOGS, 'r') as f:
        records = json.load(f)
    return sum(
        chunk['size']
        for record in records
        if record.get('backup_id') in ids
        for chunk in record.get('chunks', [])
    )


def install_dynamic_fixture():
    token = secrets.token_hex(6)
    east_a = f'east-a-{token}'
    east_b = f'east-b-{token}'
    west = f'west-{token}'
    base = 100000 + secrets.randbelow(800000)
    ids = [base + i for i in range(7)]

    if os.path.exists(DB):
        os.remove(DB)
    with sqlite3.connect(DB) as conn:
        conn.executescript("""
            CREATE TABLE servers (server_name TEXT PRIMARY KEY, region TEXT);
            CREATE TABLE backups (id INTEGER PRIMARY KEY, server_name TEXT);
            CREATE TABLE backup_metadata (backup_id INTEGER, status TEXT);
        """)
        conn.executemany('INSERT INTO servers VALUES (?, ?)', [
            (east_a, 'us-east-1'),
            (east_b, 'us-east-1'),
            (west, 'eu-west-1'),
        ])
        conn.executemany('INSERT INTO backups VALUES (?, ?)', [
            (ids[0], east_a),
            (ids[1], east_a),
            (ids[2], west),
            (ids[3], east_b),
            (ids[4], east_b),
            (ids[5], west),
        ])
        conn.executemany('INSERT INTO backup_metadata VALUES (?, ?)', [
            (ids[0], 'SUCCESS'),
            (ids[1], 'FAILED'),
            (ids[2], 'SUCCESS'),
            (ids[3], 'SUCCESS'),
            (ids[4], 'PENDING'),
            (ids[5], 'SUCCESS'),
            (ids[6], 'SUCCESS'),
        ])

    def sizes(count):
        return [{'size': 10000 + secrets.randbelow(10000)} for _ in range(count)]

    records = [
        {'backup_id': ids[0], 'chunks': sizes(3)},
        {'backup_id': ids[1], 'chunks': sizes(2)},
        {'backup_id': ids[2], 'chunks': sizes(2)},
        {'backup_id': ids[3], 'chunks': sizes(2)},
        {'backup_id': ids[4], 'chunks': sizes(1)},
        {'backup_id': ids[5], 'chunks': sizes(2)},
        {'backup_id': ids[6], 'chunks': sizes(1)},
    ]
    with open(LOGS, 'w') as f:
        json.dump(records, f)


def test_complete_backup_validation_pipeline():
    assert os.path.lexists(SCRIPT), f"Required script {SCRIPT} does not exist"
    mode = os.lstat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT} must be a regular file"
    assert mode & 0o111, f"{SCRIPT} must be executable"

    with open(SCRIPT, 'r') as f:
        source = f.read()
    active_source = '\n'.join(
        line for line in source.splitlines() if not line.lstrip().startswith('#')
    )
    assert re.search(r'\bsqlite3\b', active_source), 'The script must query SQLite'
    assert re.search(r'\bjq\b', active_source), 'The script must use jq for JSON aggregation'
    assert len(re.findall(r'\bJOIN\b', active_source, re.IGNORECASE)) >= 2, (
        'The SQL query must explicitly join the three relational tables'
    )

    original_db = open(DB, 'rb').read()
    original_logs = open(LOGS, 'rb').read()
    original_output = open(OUTPUT, 'rb').read() if os.path.exists(OUTPUT) else None
    baseline_output = None

    try:
        # Preserve the original exact assertion, but require the submitted script to create it.
        run_script(2500)
        baseline_output = open(OUTPUT, 'rb').read()

        # Replace both data sources with unpredictable values and derive the answer independently.
        install_dynamic_fixture()
        expected = reference_total()
        assert expected != 2500
        run_script(expected)
    finally:
        with open(DB, 'wb') as f:
            f.write(original_db)
        with open(LOGS, 'wb') as f:
            f.write(original_logs)
        saved_output = baseline_output if baseline_output is not None else original_output
        if saved_output is None:
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, 'wb') as f:
                f.write(saved_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
