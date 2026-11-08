#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import sqlite3
import subprocess
from pathlib import Path

import pytest

DB_PATH = '/home/user/kg.db'
RESULT_PATH = '/home/user/result.json'
HOME_PATH = Path('/home/user')


def expected_subjects():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("""
            SELECT subject FROM triples
            WHERE predicate = 'is_a' AND object = 'AI_Agent'
            INTERSECT
            SELECT subject FROM triples
            WHERE predicate = 'has_skill' AND object = 'QueryOptimization'
            INTERSECT
            SELECT subject FROM triples
            WHERE predicate = 'assigned_to' AND object = 'Project_X'
            ORDER BY subject
        """).fetchall()
        return [row[0] for row in rows]
    finally:
        conn.close()


def read_result():
    with open(RESULT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {RESULT_PATH} does not contain valid JSON.")


def test_result_file_exists():
    assert os.path.exists(RESULT_PATH), f"The file {RESULT_PATH} was not created."
    assert os.path.isfile(RESULT_PATH), f"{RESULT_PATH} is not a valid file."


def test_result_file_content():
    data = read_result()
    expected = expected_subjects()
    assert isinstance(data, list), f"Expected a JSON array, but got {type(data).__name__}."
    assert data == expected, f"Expected {expected}, but got {data}."


def test_index_created():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='triples';")
        indexes = [row[0] for row in cursor.fetchall()]
        assert len(indexes) >= 1, "No index was created on the 'triples' table. You must optimize the query by creating at least one index."

        suitable = False
        for index_name in indexes:
            quoted = index_name.replace('"', '""')
            columns = [row[2] for row in cursor.execute(f'PRAGMA index_info("{quoted}")').fetchall()]
            if [str(c).lower() for c in columns[:2]] == ['predicate', 'object']:
                suitable = True
                break
        assert suitable, "No index beginning with (predicate, object) was created on the 'triples' table."
    finally:
        conn.close()


def test_data_not_modified():
    conn = sqlite3.connect(DB_PATH)
    try:
        count = conn.execute("SELECT count(*) FROM triples;").fetchone()[0]
    finally:
        conn.close()

    assert count >= 100000, "The data in the 'triples' table appears to have been modified or deleted. Expected at least 100,000 rows."


def script_command(path):
    suffix = path.suffix.lower()
    if suffix == '.py':
        return ['python3', str(path)]
    if suffix == '.sh':
        return ['bash', str(path)]
    if suffix == '.rb':
        return ['ruby', str(path)]

    try:
        first_line = path.open('rb').readline(256).decode('utf-8', errors='ignore').lower()
    except OSError:
        return None
    if first_line.startswith('#!'):
        if 'python' in first_line:
            return ['python3', str(path)]
        if 'ruby' in first_line:
            return ['ruby', str(path)]
        if 'bash' in first_line or '/sh' in first_line:
            return ['bash', str(path)]
    return None


def run_as_user(command):
    account = pwd.getpwnam('user')

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    env = os.environ.copy()
    env.update({'HOME': '/home/user', 'USER': 'user', 'LOGNAME': 'user'})
    return subprocess.run(
        command,
        cwd='/home/user',
        env=env,
        preexec_fn=demote,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def test_pipeline_script_executes_and_creates_result():
    candidates = []
    for root, dirs, files in os.walk(HOME_PATH):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for filename in files:
            if filename.startswith('.'):
                continue
            path = Path(root) / filename
            if str(path) in (DB_PATH, RESULT_PATH) or not path.is_file():
                continue
            command = script_command(path)
            if command is not None:
                candidates.append((str(path), command))

    assert candidates, "No Python, Bash, or Ruby pipeline script was found under /home/user."
    expected = expected_subjects()
    errors = []

    for path, command in sorted(candidates):
        try:
            if os.path.lexists(RESULT_PATH):
                os.remove(RESULT_PATH)
            completed = run_as_user(command)
        except (OSError, subprocess.TimeoutExpired) as exc:
            errors.append(f"{path}: {exc}")
            continue

        if completed.returncode != 0:
            errors.append(f"{path}: exited with status {completed.returncode}")
            continue
        if not os.path.isfile(RESULT_PATH):
            errors.append(f"{path}: did not create {RESULT_PATH}")
            continue
        try:
            with open(RESULT_PATH, 'r') as f:
                data = json.load(f)
        except (OSError, json.JSONDecodeError) as exc:
            errors.append(f"{path}: created invalid JSON ({exc})")
            continue
        if isinstance(data, list) and data == expected:
            return
        errors.append(f"{path}: produced {data!r}, expected {expected!r}")

    pytest.fail("No pipeline script successfully recreated the required result. " + "; ".join(errors))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
