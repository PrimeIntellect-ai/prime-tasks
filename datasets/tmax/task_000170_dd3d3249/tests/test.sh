#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_pipeline.py
import ast
import json
import os
import secrets
import sqlite3
import subprocess
import sys
from pathlib import Path

from pymongo import MongoClient

HOME = Path('/home/user')
BACKUP = HOME / 'backup_mapper.py'
EXPLAIN = HOME / 'explain_plan.py'
PLAN = HOME / 'query_plan.json'
DB_PATH = HOME / 'analytics.db'
SEED = HOME / 'seed.json'


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def run_script(path, timeout=45):
    require(path.is_file(), f'{path} does not exist')
    result = subprocess.run(
        [sys.executable, str(path)], cwd=str(HOME), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout
    )
    output = (result.stdout + '\n' + result.stderr).lower()
    require(result.returncode == 0,
            f'{path} failed with exit code {result.returncode}:\n{result.stdout}\n{result.stderr}')
    require('database is locked' not in output and 'operationalerror' not in output,
            f'{path} encountered an SQLite locking/operational error:\n{result.stdout}\n{result.stderr}')


def remove_sqlite():
    for suffix in ('', '-wal', '-shm', '-journal'):
        try:
            os.remove(str(DB_PATH) + suffix)
        except FileNotFoundError:
            pass


def load_collection(collection, documents):
    collection.drop()
    if documents:
        collection.insert_many(documents)


def inspect_model_source():
    require(BACKUP.is_file(), '/home/user/backup_mapper.py does not exist')
    tree = ast.parse(BACKUP.read_text())
    model = None
    for node in tree.body:
        if isinstance(node, ast.ClassDef) and node.name == 'UserStats':
            model = node
            break
    require(model is not None, 'backup_mapper.py does not define a UserStats class')
    base_names = []
    for base in model.bases:
        if isinstance(base, ast.Name):
            base_names.append(base.id)
        elif isinstance(base, ast.Attribute):
            base_names.append(base.attr)
    require('BaseModel' in base_names, 'UserStats must inherit from Pydantic BaseModel')
    annotations = {}
    for node in model.body:
        if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            annotation = node.annotation
            if isinstance(annotation, ast.Name):
                annotations[node.target.id] = annotation.id
            elif isinstance(annotation, ast.Constant) and isinstance(annotation.value, str):
                annotations[node.target.id] = annotation.value
    require(annotations.get('user_id') == 'str', 'UserStats.user_id must be annotated as str')
    require(annotations.get('total_actions') == 'int', 'UserStats.total_actions must be annotated as int')
    require(annotations.get('latest_action_date') == 'str',
            'UserStats.latest_action_date must be annotated as str')


def read_rows():
    require(DB_PATH.is_file(), '/home/user/analytics.db does not exist.')
    conn = sqlite3.connect(str(DB_PATH), timeout=5)
    try:
        info = conn.execute('PRAGMA table_info(user_summary)').fetchall()
        require(info, 'user_summary table does not exist')
        columns = [row[1] for row in info]
        require(columns == ['user_id', 'total_actions', 'latest_action_date'],
                f'user_summary has incorrect columns: {columns}')
        return conn.execute(
            'SELECT user_id, total_actions, latest_action_date FROM user_summary ORDER BY user_id'
        ).fetchall()
    finally:
        conn.close()


def walk(value):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def inspect_plan(document_count, group_count, collection):
    require(PLAN.is_file(), '/home/user/query_plan.json does not exist.')
    content = PLAN.read_text()
    require('executionStats' in content, "query_plan.json does not contain 'executionStats'.")
    try:
        plan = json.loads(content)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'query_plan.json is not a valid JSON file: {exc}')
    require(isinstance(plan, dict), 'query_plan.json must contain a MongoDB explain document')

    nodes = list(walk(plan))
    stats = [node['executionStats'] for node in nodes
             if isinstance(node, dict) and isinstance(node.get('executionStats'), dict)]
    require(stats, 'query_plan.json has no actual executionStats object')
    require(any(s.get('executionSuccess') is True for s in stats),
            'MongoDB explain execution did not report success')

    commands = [node for node in nodes
                if isinstance(node, dict) and node.get('aggregate') == 'activity_logs']
    require(commands, 'query_plan.json is not an aggregation explain for activity_logs')
    pipeline = commands[0].get('pipeline')
    require(isinstance(pipeline, list), 'The explain command does not contain an aggregation pipeline')
    groups = [stage.get('$group') for stage in pipeline
              if isinstance(stage, dict) and isinstance(stage.get('$group'), dict)]
    require(groups, 'The explained pipeline does not contain a $group stage')
    group = groups[-1]
    require(group.get('_id') == '$user_id', 'The explained pipeline does not group by user_id')
    require(group.get('total_actions') == {'$sum': 1},
            'The explained pipeline does not calculate total_actions')
    require(group.get('latest_action_date') == {'$max': '$timestamp'},
            'The explained pipeline does not calculate latest_action_date')

    index_names = []
    for index in collection.list_indexes():
        keys = list(index['key'].items())
        if any(key == 'user_id' for key, _ in keys):
            index_names.append(index['name'])
    require(index_names, 'activity_logs has no index containing user_id')

    plan_text = json.dumps(plan)
    require('IXSCAN' in plan_text or 'DISTINCT_SCAN' in plan_text,
            'The aggregation explain plan does not use an index scan')
    require(any(name in plan_text for name in index_names),
            'The explain plan does not use the created user_id index')

    observed = set()
    for stat in stats:
        for node in walk(stat):
            if isinstance(node, dict):
                for key in ('nReturned', 'totalDocsExamined', 'totalKeysExamined'):
                    value = node.get(key)
                    if isinstance(value, int):
                        observed.add(value)
    require(document_count in observed or group_count in observed,
            'executionStats do not correspond to the dynamically seeded collection')


def main():
    inspect_model_source()
    require(EXPLAIN.is_file(), '/home/user/explain_plan.py does not exist')
    require(SEED.is_file(), '/home/user/seed.json does not exist')
    base_documents = json.loads(SEED.read_text())
    require(isinstance(base_documents, list), 'seed.json must contain an array')

    client = MongoClient('mongodb://localhost:27017/', serverSelectionTimeoutMS=4000)
    client.admin.command('ping')
    collection = client['analytics_db']['activity_logs']

    token = secrets.token_hex(8)
    probe_count = 2 + secrets.randbelow(4)
    valid_probe_ids = [f'VERIFY_{token}_{i}' for i in range(probe_count)]
    probes = []
    expected_probe_rows = []
    for i, user_id in enumerate(valid_probe_ids):
        first = f'2024-02-{i + 1:02d}T01:00:00Z'
        latest = f'2024-02-{i + 1:02d}T23:59:59Z'
        probes.extend([
            {'user_id': user_id, 'action': 'first', 'timestamp': first},
            {'user_id': user_id, 'action': 'last', 'timestamp': latest},
        ])
        expected_probe_rows.append((user_id, 2, latest))

    bad_missing = f'BAD_MISSING_{token}'
    bad_type = 900000000 + secrets.randbelow(999999)
    bad_iso = f'BAD_ISO_{token}'
    probes.extend([
        {'user_id': bad_missing, 'action': 'missing_timestamp'},
        {'user_id': bad_type, 'action': 'wrong_user_type', 'timestamp': '2024-03-01T00:00:00Z'},
        {'user_id': bad_iso, 'action': 'bad_date', 'timestamp': 'not-an-iso-date'},
    ])
    dynamic_documents = base_documents + probes

    load_collection(collection, dynamic_documents)
    remove_sqlite()
    run_script(BACKUP)
    run_script(EXPLAIN)

    expected_dynamic = sorted([
        ('U001', 3, '2023-10-01T11:00:00Z'),
        ('U002', 2, '2023-10-01T11:30:00Z'),
        ('U003', 1, '2023-10-01T10:02:00Z'),
        *expected_probe_rows,
    ])
    rows = read_rows()
    require(rows == expected_dynamic,
            f'Expected validated dynamic records {expected_dynamic}, but got {rows}')

    group_count = len({(type(doc.get('user_id')).__name__, repr(doc.get('user_id')))
                       for doc in dynamic_documents})
    inspect_plan(len(dynamic_documents), group_count, collection)

    # Restore the instructed final state and retain the original verifier assertions.
    load_collection(collection, base_documents)
    remove_sqlite()
    run_script(BACKUP)
    run_script(EXPLAIN)

    rows = read_rows()
    expected_full = [
        ('U001', 3, '2023-10-01T11:00:00Z'),
        ('U002', 2, '2023-10-01T11:30:00Z'),
        ('U003', 1, '2023-10-01T10:02:00Z'),
    ]
    require(rows == expected_full,
            f'Expected final records {expected_full}, but got {rows}')
    expected_original = [('U001', 3), ('U002', 2), ('U003', 1)]
    original_rows = [(row[0], row[1]) for row in rows]
    require(original_rows == expected_original,
            f'Expected records {expected_original}, but got {original_rows}. Pydantic validation or insertion logic is incorrect.')

    final_group_count = len({(type(doc.get('user_id')).__name__, repr(doc.get('user_id')))
                             for doc in base_documents})
    inspect_plan(len(base_documents), final_group_count, collection)
    client.close()


if __name__ == '__main__':
    main()
PY_EOF

if timeout 150 python3 /tmp/verify_pipeline.py; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
