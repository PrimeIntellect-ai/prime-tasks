#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import datetime
import os
import random
import shlex
import sqlite3
import subprocess
from pathlib import Path
from zoneinfo import ZoneInfo

REPRO_PATH = Path('/home/user/minimal_repro.py')
IDS_PATH = Path('/home/user/correct_ids.txt')
DB_PATH = Path('/home/user/events.db')
REPORT_PATH = Path('/home/user/report.py')

EXPECTED_REPORT = '''import sqlite3
import time

def generate_report():
    conn = sqlite3.connect('/home/user/events.db')
    cursor = conn.cursor()
    cursor.execute("SELECT id FROM logs WHERE event_time LIKE '2024-05-01%'")
    results = cursor.fetchall()
    print("Report results:", results)
    conn.close()

if __name__ == "__main__":
    generate_report()
    time.sleep(999999)
'''


def read_ids():
    content = IDS_PATH.read_text().strip()
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert all(line.lstrip('-').isdigit() for line in lines), 'correct_ids.txt must contain only integer IDs, one per line.'
    return [int(line) for line in lines]


def run_repro():
    first_line = REPRO_PATH.read_bytes().splitlines()[0].decode('utf-8', errors='replace')
    if first_line.startswith('#!'):
        command = shlex.split(first_line[2:].strip()) + [str(REPRO_PATH)]
    else:
        command = ['python3', str(REPRO_PATH)]
    result = subprocess.run(command, cwd='/home/user', text=True, capture_output=True, timeout=20)
    assert result.returncode == 0, f'minimal_repro.py failed with exit code {result.returncode}. stdout: {result.stdout!r}; stderr: {result.stderr!r}'
    assert IDS_PATH.is_file(), 'Running minimal_repro.py did not create /home/user/correct_ids.txt.'


def test_minimal_repro_exists():
    repro_path = "/home/user/minimal_repro.py"
    assert os.path.isfile(repro_path), f"The file {repro_path} does not exist. You must create a minimal reproducible example."
    assert os.path.getsize(repro_path) > 0, f"The file {repro_path} is empty."


def test_correct_ids_txt():
    ids_path = "/home/user/correct_ids.txt"
    assert os.path.isfile(ids_path), f"The file {ids_path} does not exist."

    with open(ids_path, 'r') as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 IDs in {ids_path}, but found {len(lines)}."
    assert lines[0] == "2", f"Expected first ID to be '2', but got '{lines[0]}'."
    assert lines[1] == "3", f"Expected second ID to be '3', but got '{lines[1]}'."


def test_deleted_report_was_recovered():
    assert REPORT_PATH.is_file(), 'The deleted /home/user/report.py was not recovered.'
    assert REPORT_PATH.stat().st_size > 0, 'The recovered /home/user/report.py is empty.'
    try:
        recovered_tree = ast.dump(ast.parse(REPORT_PATH.read_text()), include_attributes=False)
    except (OSError, UnicodeDecodeError, SyntaxError) as exc:
        raise AssertionError(f'The recovered report.py is not valid recovered Python source: {exc}')
    expected_tree = ast.dump(ast.parse(EXPECTED_REPORT), include_attributes=False)
    assert recovered_tree == expected_tree, 'The recovered report.py does not contain the source code of the deleted running script.'


def test_repro_executes_and_queries_database_correctly():
    original_db = DB_PATH.read_bytes()
    original_ids = IDS_PATH.read_bytes() if IDS_PATH.exists() else None
    temp_db = DB_PATH.with_name('events.verifier.tmp.db')

    try:
        IDS_PATH.unlink(missing_ok=True)
        run_repro()
        assert read_ids() == [2, 3], 'Executing minimal_repro.py against the original database did not produce IDs 2 and 3 in ascending order.'

        rng = random.SystemRandom()
        ids = rng.sample(range(10000, 1000000), 7)
        timestamps = [
            '2024-05-01T03:59:59Z',
            '2024-05-01T04:00:00Z',
            '2024-05-01T16:37:21Z',
            '2024-05-02T03:59:59Z',
            '2024-05-02T04:00:00Z',
            '2024-04-30T15:00:00Z',
            '2024-05-02T18:00:00Z',
        ]
        rows = list(zip(ids, timestamps, ['FAIL', 'SUCCESS', 'FAIL', 'SUCCESS', 'FAIL', 'SUCCESS', 'FAIL']))
        rng.shuffle(rows)

        temp_db.unlink(missing_ok=True)
        conn = sqlite3.connect(temp_db)
        try:
            conn.execute('CREATE TABLE logs (id INTEGER PRIMARY KEY, event_time TEXT, status TEXT)')
            conn.executemany('INSERT INTO logs VALUES (?, ?, ?)', rows)
            conn.commit()
        finally:
            conn.close()
        os.replace(temp_db, DB_PATH)

        eastern = ZoneInfo('US/Eastern')
        target_date = datetime.date(2024, 5, 1)
        expected = sorted(
            event_id for event_id, event_time, _ in rows
            if datetime.datetime.fromisoformat(event_time.replace('Z', '+00:00')).astimezone(eastern).date() == target_date
        )

        IDS_PATH.unlink(missing_ok=True)
        run_repro()
        actual = read_ids()
        assert actual == sorted(actual), 'IDs written by minimal_repro.py are not sorted in ascending order.'
        assert actual == expected, f'minimal_repro.py returned {actual}, but the database rows belonging to 2024-05-01 in US/Eastern are {expected}.'
    finally:
        temp_db.unlink(missing_ok=True)
        DB_PATH.write_bytes(original_db)
        if original_ids is None:
            IDS_PATH.unlink(missing_ok=True)
        else:
            IDS_PATH.write_bytes(original_ids)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
