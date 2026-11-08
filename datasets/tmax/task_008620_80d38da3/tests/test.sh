#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest

JSON_PATH = '/home/user/restore_chain.json'
DB_PATH = '/home/user/backup_catalog.db'


def test_json_file_exists():
    assert os.path.exists(JSON_PATH), f"The file {JSON_PATH} does not exist."
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is not a regular file."


def test_json_content():
    try:
        with open(JSON_PATH, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")

    expected_data = [
        {"job_id": 5, "job_name": "Full_DB_Backup_Jan1"},
        {"job_id": 12, "job_name": "Inc_DB_Backup_Jan2"},
        {"job_id": 24, "job_name": "Inc_DB_Backup_Jan3"},
        {"job_id": 45, "job_name": "Inc_DB_Backup_Jan4"},
        {"job_id": 73, "job_name": "Inc_DB_Backup_Jan5"}
    ]

    assert isinstance(data, list), "The JSON root must be a list (array)."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items in the array, but found {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        assert "job_id" in actual, f"Item at index {i} is missing the 'job_id' key."
        assert "job_name" in actual, f"Item at index {i} is missing the 'job_name' key."
        assert len(actual.keys()) == 2, f"Item at index {i} should contain exactly two keys ('job_id' and 'job_name')."

        assert actual["job_id"] == expected["job_id"], f"Item at index {i} has incorrect 'job_id'. Expected {expected['job_id']}, got {actual['job_id']}."
        assert actual["job_name"] == expected["job_name"], f"Item at index {i} has incorrect 'job_name'. Expected '{expected['job_name']}', got '{actual['job_name']}'."


def _candidate_command(path):
    suffix = path.suffix.lower()
    if suffix == '.py':
        return ['python3', str(path)]
    if suffix in ('.sh', '.bash'):
        return ['bash', str(path)]
    if suffix == '.sql':
        return ['sqlite3', DB_PATH], path.read_text(errors='ignore')

    first_line = path.read_text(errors='ignore').splitlines()[:1]
    first_line = first_line[0] if first_line else ''
    if 'python' in first_line:
        return ['python3', str(path)]
    if first_line.startswith('#!') and ('sh' in first_line or 'bash' in first_line):
        return ['bash', str(path)]
    if path.stat().st_mode & stat.S_IXUSR:
        return [str(path)]
    return None


def _valid_dynamic_json(expected):
    try:
        with open(JSON_PATH, 'r') as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return False

    if not isinstance(data, list) or len(data) != len(expected):
        return False
    for actual, wanted in zip(data, expected):
        if not isinstance(actual, dict) or set(actual) != {'job_id', 'job_name'}:
            return False
        if type(actual['job_id']) is not int or type(actual['job_name']) is not str:
            return False
        if actual != wanted:
            return False
    return True


def test_recursive_cte_artifact_executes_against_changed_catalog():
    candidates = []
    for path in Path('/home/user').rglob('*'):
        if not path.is_file() or str(path) in (JSON_PATH, DB_PATH):
            continue
        try:
            if path.stat().st_size > 2_000_000:
                continue
            source = path.read_text(errors='ignore')
        except OSError:
            continue
        if re.search(r'\bWITH\s+RECURSIVE\b', source, re.IGNORECASE):
            command = _candidate_command(path)
            if command is not None:
                candidates.append((path, command))

    assert candidates, "No runnable artifact containing a recursive SQL CTE was found under /home/user."

    token = secrets.token_hex(8)
    new_root_id = 1_500_000_000 + secrets.randbelow(500_000_000)
    chain_ids = [5, 12, 24, 45, 73]

    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "INSERT INTO backup_jobs VALUES (?, ?, NULL, ?, ?)",
        (new_root_id, f'Dynamic_Root_{token}', 7777777, 'SUCCESS')
    )
    conn.execute("UPDATE backup_jobs SET parent_job_id = ? WHERE job_id = 5", (new_root_id,))
    for job_id in chain_ids:
        conn.execute(
            "UPDATE backup_jobs SET job_name = ? WHERE job_id = ?",
            (f'Dynamic_Job_{job_id}_{token}', job_id)
        )
    conn.commit()

    rows = conn.execute('''
        WITH RECURSIVE restore_chain(job_id, job_name, parent_job_id, depth) AS (
            SELECT job_id, job_name, parent_job_id, 0
            FROM backup_jobs WHERE job_id = 73
            UNION ALL
            SELECT b.job_id, b.job_name, b.parent_job_id, rc.depth + 1
            FROM backup_jobs AS b
            JOIN restore_chain AS rc ON b.job_id = rc.parent_job_id
        )
        SELECT job_id, job_name FROM restore_chain ORDER BY depth DESC
    ''').fetchall()
    conn.close()
    expected = [{'job_id': row[0], 'job_name': row[1]} for row in rows]

    with tempfile.TemporaryDirectory() as temp_dir:
        temp = Path(temp_dir)
        baseline = temp / 'catalog.db'
        shutil.copy2(DB_PATH, baseline)
        trace_path = temp / 'sql_trace.log'

        sitecustomize = temp / 'sitecustomize.py'
        sitecustomize.write_text(
            "import sqlite3\n"
            f"_trace_log = {str(trace_path)!r}\n"
            "_real_connect = sqlite3.connect\n"
            "def _record(statement):\n"
            "    try:\n"
            "        with open(_trace_log, 'a') as f:\n"
            "            f.write(statement + '\\n')\n"
            "    except Exception:\n"
            "        pass\n"
            "def connect(*args, **kwargs):\n"
            "    connection = _real_connect(*args, **kwargs)\n"
            "    connection.set_trace_callback(_record)\n"
            "    return connection\n"
            "sqlite3.connect = connect\n"
        )

        bin_dir = temp / 'bin'
        bin_dir.mkdir()
        sqlite_wrapper = bin_dir / 'sqlite3'
        sqlite_wrapper.write_text(
            '#!/bin/sh\n'
            f'exec /usr/bin/sqlite3 -cmd ".trace {trace_path}" "$@"\n'
        )
        sqlite_wrapper.chmod(0o755)

        failures = []
        for path, command_spec in candidates:
            shutil.copy2(baseline, DB_PATH)
            try:
                os.remove(JSON_PATH)
            except FileNotFoundError:
                pass
            trace_path.write_text('')

            stdin_text = None
            command = command_spec
            if isinstance(command_spec, tuple):
                command, stdin_text = command_spec

            env = os.environ.copy()
            env['PYTHONPATH'] = str(temp) + (':' + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
            env['PATH'] = str(bin_dir) + ':' + env.get('PATH', '')

            try:
                result = subprocess.run(
                    command,
                    input=stdin_text,
                    cwd='/home/user',
                    env=env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=20
                )
            except Exception as exc:
                failures.append(f'{path}: {exc}')
                continue

            try:
                trace = trace_path.read_text(errors='ignore')
            except OSError:
                trace = ''

            used_recursive_cte = bool(re.search(r'\bWITH\s+RECURSIVE\b', trace, re.IGNORECASE))
            if result.returncode == 0 and used_recursive_cte and _valid_dynamic_json(expected):
                return
            failures.append(
                f'{path}: exit={result.returncode}, recursive_cte_executed={used_recursive_cte}, '
                f'output_correct={_valid_dynamic_json(expected)}'
            )

    pytest.fail("No submitted artifact executed a recursive CTE and generated the correct dynamic chain. " + '; '.join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
