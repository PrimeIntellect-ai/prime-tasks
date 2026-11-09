#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import pwd
import sqlite3
import subprocess
import tempfile
import uuid

import pytest

DB_PATH = '/home/user/service_backup.db'
JSON_PATH = '/home/user/graph_materialized.json'

EXPECTED_ENTITIES = [
    (1, 'gateway-svc'),
    (2, 'auth-svc'),
    (3, 'user-db'),
    (4, 'payment-svc'),
    (5, 'payment-db'),
    (6, 'cache-node-1'),
    (7, 'cache-node-2'),
    (8, 'worker-queue'),
]
EXPECTED_LINKS = [
    (1, 1, 2),
    (2, 1, 4),
    (3, 2, 3),
    (4, 4, 5),
    (5, 2, 6),
    (6, 2, 7),
    (7, 4, 8),
]


def read_database_state():
    conn = sqlite3.connect(DB_PATH)
    try:
        cur = conn.cursor()
        cur.execute('SELECT ent_id, ent_identifier FROM tbl_entity_registry ORDER BY ent_id')
        entities = cur.fetchall()
        cur.execute('SELECT link_id, parent_ent_id, child_ent_id FROM tbl_entity_links ORDER BY link_id')
        links = cur.fetchall()
        cur.execute("SELECT name FROM sqlite_master WHERE type='index' AND sql IS NOT NULL ORDER BY name")
        explicit_indexes = [row[0] for row in cur.fetchall()]
        return entities, links, explicit_indexes
    finally:
        conn.close()


def find_python_scripts():
    candidates = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for filename in files:
            path = os.path.join(root, filename)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            try:
                with open(path, 'rb') as f:
                    raw = f.read()
                text = raw.decode('utf-8')
            except (OSError, UnicodeDecodeError):
                continue

            first_line = text.splitlines()[0] if text.splitlines() else ''
            if not (filename.endswith('.py') or (first_line.startswith('#!') and 'python' in first_line.lower())):
                continue
            try:
                ast.parse(text, filename=path)
            except SyntaxError:
                continue

            score = 0
            if DB_PATH in text or 'service_backup.db' in text:
                score += 2
            if JSON_PATH in text or 'graph_materialized.json' in text:
                score += 2
            if 'sqlite3' in text:
                score += 1
            if 'json' in text:
                score += 1
            candidates.append((score, path))

    candidates.sort(key=lambda item: (-item[0], item[1]))
    return [path for _, path in candidates]


def restore_database(snapshot_path):
    for suffix in ('', '-wal', '-shm'):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass

    source = sqlite3.connect(snapshot_path)
    destination = sqlite3.connect(DB_PATH)
    try:
        source.backup(destination)
    finally:
        destination.close()
        source.close()
    os.chmod(DB_PATH, 0o666)


@pytest.fixture(scope='session', autouse=True)
def verify_and_execute_submission():
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"

    # The submitted work must have preserved every original entity and link and
    # must already have dropped the original explicit secondary index.
    entities, links, explicit_indexes = read_database_state()
    assert entities == EXPECTED_ENTITIES, 'The original entity registry was modified or truncated.'
    assert links == EXPECTED_LINKS, 'The original relationship table was modified or truncated.'
    assert explicit_indexes == [], f'Found unexpected secondary indexes before verification: {explicit_indexes}'

    scripts = find_python_scripts()
    assert scripts, 'No Python script was found under /home/user.'

    fd, snapshot_path = tempfile.mkstemp(prefix='service_backup_snapshot_', suffix='.db')
    os.close(fd)
    os.remove(snapshot_path)
    source = sqlite3.connect(DB_PATH)
    snapshot = sqlite3.connect(snapshot_path)
    try:
        source.backup(snapshot)
    finally:
        snapshot.close()
        source.close()

    user = pwd.getpwnam('user')
    failures = []
    succeeded = False

    for script_path in scripts:
        restore_database(snapshot_path)

        # Use an unpredictable explicit index name so the submitted script must
        # actually enumerate and drop all secondary indexes.
        probe_index = 'verifier_probe_' + uuid.uuid4().hex
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute(f'CREATE INDEX "{probe_index}" ON tbl_entity_links(parent_ent_id)')
            conn.commit()
        finally:
            conn.close()

        try:
            os.remove(JSON_PATH)
        except FileNotFoundError:
            pass

        def demote():
            os.setgroups([])
            os.setgid(user.pw_gid)
            os.setuid(user.pw_uid)

        try:
            result = subprocess.run(
                ['python3', script_path],
                cwd='/home/user',
                env={**os.environ, 'HOME': '/home/user', 'USER': 'user'},
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
                preexec_fn=demote,
            )
        except Exception as exc:
            failures.append(f'{script_path}: {exc}')
            continue

        if result.returncode != 0:
            failures.append(f'{script_path}: exited {result.returncode}: {result.stderr[-500:]}')
            continue

        try:
            after_entities, after_links, after_indexes = read_database_state()
        except Exception as exc:
            failures.append(f'{script_path}: database unreadable after execution: {exc}')
            continue

        if after_entities != EXPECTED_ENTITIES or after_links != EXPECTED_LINKS:
            failures.append(f'{script_path}: modified or deleted original database rows')
            continue
        if after_indexes:
            failures.append(f'{script_path}: did not drop indexes {after_indexes}')
            continue
        if not os.path.isfile(JSON_PATH):
            failures.append(f'{script_path}: did not create {JSON_PATH}')
            continue

        succeeded = True
        break

    try:
        os.remove(snapshot_path)
    except FileNotFoundError:
        pass

    assert succeeded, 'No submitted Python script successfully performed the task. ' + ' | '.join(failures)


def test_secondary_indexes_dropped():
    """Verify that all secondary indexes have been dropped from the database."""
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    # Fetch all indexes
    cur.execute("SELECT name, sql FROM sqlite_master WHERE type='index';")
    indexes = cur.fetchall()
    conn.close()

    # We expect no secondary indexes. SQLite might have auto-indexes for UNIQUE constraints
    # (like sqlite_autoindex_tbl_entity_registry_1). These have sql=None.
    # Any index created explicitly with CREATE INDEX will have a non-NULL sql.
    explicit_indexes = [name for name, sql in indexes if sql is not None]

    assert len(explicit_indexes) == 0, f"Found unexpected secondary indexes: {explicit_indexes}"


def test_json_output_exists_and_valid():
    """Verify the JSON file exists and is valid JSON."""
    assert os.path.exists(JSON_PATH), f"Output JSON file missing at {JSON_PATH}"

    with open(JSON_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"File {JSON_PATH} contains invalid JSON: {e}")

    assert isinstance(data, dict), "JSON root must be an object (dictionary)"


def test_json_output_matches_database():
    """Recompute the graph from the database and verify it matches the JSON output."""
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"
    assert os.path.exists(JSON_PATH), f"Output JSON file missing at {JSON_PATH}"

    # Recompute the expected graph
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    # Fetch all entities
    cur.execute("SELECT ent_id, ent_identifier FROM tbl_entity_registry")
    entities = {row[0]: row[1] for row in cur.fetchall()}

    # Fetch all links
    cur.execute("SELECT parent_ent_id, child_ent_id FROM tbl_entity_links")
    links = cur.fetchall()

    conn.close()

    expected_graph = {}
    for parent_id, child_id in links:
        parent_name = entities[parent_id]
        child_name = entities[child_id]

        if parent_name not in expected_graph:
            expected_graph[parent_name] = []
        expected_graph[parent_name].append(child_name)

    for parent in expected_graph:
        expected_graph[parent].sort()

    # Read actual JSON
    with open(JSON_PATH, 'r') as f:
        actual_graph = json.load(f)

    assert actual_graph == expected_graph, "The materialized graph does not match the expected adjacency list derived from the database."


def test_json_formatting():
    """Verify the JSON file is nicely formatted with indent=4."""
    assert os.path.exists(JSON_PATH), f"Output JSON file missing at {JSON_PATH}"

    with open(JSON_PATH, 'r') as f:
        content = f.read()

    # A simple heuristic: if it has newlines and spaces, it's likely formatted.
    # We can parse it and dump it with indent=4 and see if it closely matches.
    data = json.loads(content)
    expected_content = json.dumps(data, indent=4)

    # We check if the content has newlines and spaces for indentation
    assert "\n" in content, "JSON file does not appear to be formatted with newlines."
    assert "    " in content, "JSON file does not appear to be formatted with an indent of 4 spaces."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
