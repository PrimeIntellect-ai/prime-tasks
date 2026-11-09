#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import json
import os
import shutil
import sqlite3
import stat
import subprocess
import tempfile

import jsonschema
import pytest

SCRIPT_PATH = '/home/user/etl_pipeline.py'
JSON_PATH = '/home/user/top_users.json'
DB_PATH = '/home/user/communications.db'
SCHEMA_PATH = '/home/user/schema.json'


def expected_from_database():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    query = """
    SELECT u.handle,
           (SELECT COUNT(*) FROM event_links WHERE source_uid = u.uid OR target_uid = u.uid) as score
    FROM system_users u
    WHERE (SELECT COUNT(*) FROM event_links WHERE source_uid = u.uid OR target_uid = u.uid) > 2
    ORDER BY score DESC, u.handle ASC
    LIMIT 3
    """
    try:
        cur.execute(query)
        rows = cur.fetchall()
    except sqlite3.Error as e:
        pytest.fail(f"Failed to query database {DB_PATH}: {e}")
    finally:
        conn.close()
    return [{"username": row[0], "communication_score": row[1]} for row in rows]


def run_pipeline():
    try:
        return subprocess.run(
            ['python3', SCRIPT_PATH],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('etl_pipeline.py did not finish within 30 seconds')


def load_output():
    assert os.path.isfile(JSON_PATH), f"File {JSON_PATH} does not exist."
    try:
        with open(JSON_PATH, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {JSON_PATH} does not contain valid JSON.")


def assert_pipeline_output(expected):
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    result = run_pipeline()
    assert result.returncode == 0, (
        f"etl_pipeline.py exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    actual_data = load_output()
    assert isinstance(actual_data, list), (
        f"Expected JSON root to be a list, but got {type(actual_data).__name__}"
    )
    assert actual_data == expected, (
        f"Data in {JSON_PATH} does not match the expected output. "
        f"Expected: {expected}, Actual: {actual_data}"
    )
    with open(SCHEMA_PATH, 'r') as f:
        schema = json.load(f)
    jsonschema.validate(actual_data, schema)


def test_top_users_output_and_pipeline():
    assert os.path.exists(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist."
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode) and not os.path.islink(SCRIPT_PATH), (
        f"{SCRIPT_PATH} must be a regular Python script."
    )
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} is missing."
    assert os.path.isfile(SCHEMA_PATH), f"Schema {SCHEMA_PATH} is missing."

    schema_bytes = open(SCHEMA_PATH, 'rb').read()
    schema_mode = stat.S_IMODE(os.stat(SCHEMA_PATH).st_mode)
    db_mode = stat.S_IMODE(os.stat(DB_PATH).st_mode)

    fd, db_backup = tempfile.mkstemp(prefix='communications-backup-', suffix='.db')
    os.close(fd)
    source = sqlite3.connect(DB_PATH)
    backup = sqlite3.connect(db_backup)
    try:
        source.backup(backup)
    finally:
        backup.close()
        source.close()

    try:
        # Exercise the submitted script on a database state not present during
        # development, with expected answers independently derived here.
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        cur.execute('SELECT COALESCE(MAX(uid), 0) + 1 FROM system_users')
        probe_uid = cur.fetchone()[0]
        cur.execute(
            'INSERT INTO system_users(uid, handle) VALUES (?, ?)',
            (probe_uid, 'verifier_probe_user'),
        )
        cur.execute('SELECT COALESCE(MAX(msg_id), 0) FROM message_meta')
        next_msg = cur.fetchone()[0] + 1
        cur.execute('SELECT COALESCE(MAX(event_id), 0) FROM event_links')
        next_event = cur.fetchone()[0] + 1
        for offset in range(7):
            msg_id = next_msg + offset
            cur.execute(
                'INSERT INTO message_meta(msg_id, content) VALUES (?, ?)',
                (msg_id, f'verifier probe {offset}'),
            )
            cur.execute(
                'INSERT INTO event_links(event_id, msg_id, source_uid, target_uid) '
                'VALUES (?, ?, ?, ?)',
                (next_event + offset, msg_id, probe_uid, 5),
            )
        conn.commit()
        conn.close()

        changed_expected = expected_from_database()
        assert changed_expected and changed_expected[0]['username'] == 'verifier_probe_user'
        assert_pipeline_output(changed_expected)

        # Make the supplied schema reject the nonempty result. A pipeline that
        # validates before writing must not leave an invalid output on disk.
        with open(SCHEMA_PATH, 'r') as f:
            restrictive_schema = copy.deepcopy(json.load(f))
        restrictive_schema['maxItems'] = 0
        with open(SCHEMA_PATH, 'w') as f:
            json.dump(restrictive_schema, f)
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        run_pipeline()
        assert not os.path.exists(JSON_PATH), (
            'etl_pipeline.py wrote top_users.json even though its result did not '
            'validate against the schema; validation must occur before writing.'
        )
    finally:
        for suffix in ('', '-wal', '-shm'):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.remove(path)
        shutil.copyfile(db_backup, DB_PATH)
        os.chmod(DB_PATH, db_mode)
        os.remove(db_backup)
        with open(SCHEMA_PATH, 'wb') as f:
            f.write(schema_bytes)
        os.chmod(SCHEMA_PATH, schema_mode)

    # Preserve the original assertion against the restored database and leave
    # the requested final artifact in place.
    expected_data = expected_from_database()
    assert_pipeline_output(expected_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
