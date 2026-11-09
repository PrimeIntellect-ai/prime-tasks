#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3
import subprocess
import sys
import tempfile
import shutil
import uuid
import pytest

DB_PATH = '/home/user/backup_metadata.db'
JSON_PATH = '/home/user/restore_plan.json'
SCRIPT_PATH = '/home/user/build_restore.py'
TARGET_SERVICE = 'PaymentGateway'

def get_db_data():
    return get_db_data_for_target(TARGET_SERVICE)

def get_db_data_for_target(target):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Recursively find all dependencies
    query = """
    WITH RECURSIVE dep_tree AS (
        SELECT id, name FROM services WHERE name = ?
        UNION
        SELECT s.id, s.name
        FROM services s
        JOIN dependencies d ON s.id = d.depends_on_id
        JOIN dep_tree dt ON dt.id = d.service_id
    )
    SELECT id, name FROM dep_tree;
    """
    cursor.execute(query, (target,))
    services = cursor.fetchall()

    service_backups = {}
    for s in services:
        cursor.execute("""
            SELECT s3_uri, completion_time
            FROM backup_logs
            WHERE service_id = ? AND status = 'SUCCESS'
            ORDER BY completion_time DESC
            LIMIT 1
        """, (s['id'],))
        backup = cursor.fetchone()
        if backup:
            service_backups[s['name']] = {
                's3_uri': backup['s3_uri'],
                'backup_time': backup['completion_time']
            }

    # Get dependency pairs for ordering checks
    cursor.execute("""
        SELECT s1.name as service, s2.name as depends_on
        FROM dependencies d
        JOIN services s1 ON d.service_id = s1.id
        JOIN services s2 ON d.depends_on_id = s2.id
    """)
    deps = cursor.fetchall()

    conn.close()
    return service_backups, [(d['service'], d['depends_on']) for d in deps]

def validate_plan(target):
    assert os.path.exists(JSON_PATH), f"Expected output file {JSON_PATH} does not exist."
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is not a file."

    with open(JSON_PATH, 'r') as f:
        try:
            plan = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{JSON_PATH} contains invalid JSON.")

    assert isinstance(plan, list), f"JSON root must be an array, got {type(plan).__name__}."
    expected_backups, all_deps = get_db_data_for_target(target)

    actual_services = []
    for item in plan:
        assert isinstance(item, dict), "Each item in the restore plan must be a JSON object."
        assert 'service_name' in item, "Missing 'service_name' in plan item."
        assert 's3_uri' in item, "Missing 's3_uri' in plan item."
        assert 'backup_time' in item, "Missing 'backup_time' in plan item."
        actual_services.append(item['service_name'])

    assert set(actual_services) == set(expected_backups.keys()), \
        f"Expected services {set(expected_backups.keys())}, but got {set(actual_services)}."
    assert len(actual_services) == len(set(actual_services)), "Duplicate services found in the restore plan."

    for item in plan:
        svc = item['service_name']
        expected = expected_backups[svc]
        assert item['s3_uri'] == expected['s3_uri'], \
            f"Incorrect s3_uri for {svc}. Expected {expected['s3_uri']}, got {item['s3_uri']}."
        assert item['backup_time'] == expected['backup_time'], \
            f"Incorrect backup_time for {svc}. Expected {expected['backup_time']}, got {item['backup_time']}."

    indices = {name: idx for idx, name in enumerate(actual_services)}
    for service, depends_on in all_deps:
        if service in indices and depends_on in indices:
            assert indices[depends_on] < indices[service], \
                f"Topological sort violation: {service} depends on {depends_on}, so {depends_on} must be restored before {service}."

def test_restore_plan_exists():
    assert os.path.exists(JSON_PATH), f"Expected output file {JSON_PATH} does not exist."
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is not a file."

def test_restore_plan_contents_and_order():
    with open(JSON_PATH, 'r') as f:
        try:
            plan = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{JSON_PATH} contains invalid JSON.")

    assert isinstance(plan, list), f"JSON root must be an array, got {type(plan).__name__}."

    expected_backups, all_deps = get_db_data()

    # Check that the plan contains exactly the expected services
    actual_services = []
    for item in plan:
        assert isinstance(item, dict), "Each item in the restore plan must be a JSON object."
        assert 'service_name' in item, "Missing 'service_name' in plan item."
        assert 's3_uri' in item, "Missing 's3_uri' in plan item."
        assert 'backup_time' in item, "Missing 'backup_time' in plan item."
        actual_services.append(item['service_name'])

    assert set(actual_services) == set(expected_backups.keys()), \
        f"Expected services {set(expected_backups.keys())}, but got {set(actual_services)}."

    assert len(actual_services) == len(set(actual_services)), "Duplicate services found in the restore plan."

    # Check data correctness
    for item in plan:
        svc = item['service_name']
        expected = expected_backups[svc]
        assert item['s3_uri'] == expected['s3_uri'], \
            f"Incorrect s3_uri for {svc}. Expected {expected['s3_uri']}, got {item['s3_uri']}."
        assert item['backup_time'] == expected['backup_time'], \
            f"Incorrect backup_time for {svc}. Expected {expected['backup_time']}, got {item['backup_time']}."

    # Check topological sort
    # If A depends on B, B must appear before A in the plan.
    # all_deps is a list of (A, B) meaning A depends on B.
    indices = {name: idx for idx, name in enumerate(actual_services)}

    for service, depends_on in all_deps:
        if service in indices and depends_on in indices:
            idx_service = indices[service]
            idx_depends_on = indices[depends_on]
            assert idx_depends_on < idx_service, \
                f"Topological sort violation: {service} depends on {depends_on}, " \
                f"so {depends_on} must be restored before {service}."

def test_build_restore_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."

def run_script(target):
    if os.path.lexists(JSON_PATH):
        if os.path.isdir(JSON_PATH) and not os.path.islink(JSON_PATH):
            shutil.rmtree(JSON_PATH)
        else:
            os.remove(JSON_PATH)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH, target],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, \
        f"build_restore.py failed for {target}. stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    validate_plan(target)

def test_build_restore_script_executes_and_handles_database_data():
    fd, db_backup = tempfile.mkstemp(prefix='backup_metadata_', suffix='.db')
    os.close(fd)
    shutil.copy2(DB_PATH, db_backup)
    with open(JSON_PATH, 'rb') as f:
        original_json = f.read()

    try:
        # Execute the exact command requested by the task and verify its newly-created output.
        run_script(TARGET_SERVICE)

        # Add an unpredictable target and graph so a hardcoded PaymentGateway writer cannot pass.
        token = uuid.uuid4().hex
        names = {
            'root': f'DynamicRoot_{token}',
            'left': f'DynamicLeft_{token}',
            'right': f'DynamicRight_{token}',
            'leaf': f'DynamicLeaf_{token}',
            'unrelated': f'DynamicUnrelated_{token}',
        }

        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        ids = {}
        for key, name in names.items():
            cur.execute('INSERT INTO services(name) VALUES (?)', (name,))
            ids[key] = cur.lastrowid

        cur.executemany(
            'INSERT INTO dependencies(service_id, depends_on_id) VALUES (?, ?)',
            [
                (ids['root'], ids['left']),
                (ids['root'], ids['right']),
                (ids['left'], ids['leaf']),
                (ids['right'], ids['leaf']),
            ],
        )

        for index, key in enumerate(('root', 'left', 'right', 'leaf'), start=1):
            # Insert the newest successful backup before an older success so row/job order is insufficient.
            cur.execute(
                'INSERT INTO backup_logs(service_id, s3_uri, status, completion_time) VALUES (?, ?, ?, ?)',
                (ids[key], f's3://dynamic/{token}/{key}/latest.tar.gz', 'SUCCESS',
                 f'2040-01-{index:02d} 12:00:00'),
            )
            cur.execute(
                'INSERT INTO backup_logs(service_id, s3_uri, status, completion_time) VALUES (?, ?, ?, ?)',
                (ids[key], f's3://dynamic/{token}/{key}/old.tar.gz', 'SUCCESS',
                 f'2030-01-{index:02d} 12:00:00'),
            )
            cur.execute(
                'INSERT INTO backup_logs(service_id, s3_uri, status, completion_time) VALUES (?, ?, ?, ?)',
                (ids[key], f's3://dynamic/{token}/{key}/failed.tar.gz', 'FAILED',
                 f'2050-01-{index:02d} 12:00:00'),
            )
        conn.commit()
        conn.close()

        run_script(names['root'])
    finally:
        if os.path.lexists(DB_PATH):
            if os.path.isdir(DB_PATH) and not os.path.islink(DB_PATH):
                shutil.rmtree(DB_PATH)
            else:
                os.remove(DB_PATH)
        shutil.copy2(db_backup, DB_PATH)
        os.remove(db_backup)

        if os.path.lexists(JSON_PATH):
            if os.path.isdir(JSON_PATH) and not os.path.islink(JSON_PATH):
                shutil.rmtree(JSON_PATH)
            else:
                os.remove(JSON_PATH)
        with open(JSON_PATH, 'wb') as f:
            f.write(original_json)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
