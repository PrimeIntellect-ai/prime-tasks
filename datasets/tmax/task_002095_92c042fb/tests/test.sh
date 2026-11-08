#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import json
import os
import random
import re
import secrets
import subprocess
import tempfile
from urllib.parse import urlparse

import psycopg2
import pytest
import redis
from dotenv import dotenv_values
from pymongo import MongoClient


def _service_urls():
    values = {k: str(v) for k, v in dotenv_values('/app/.env').items() if v is not None}
    urls = list(values.values())

    def find(schemes):
        for value in urls:
            try:
                if urlparse(value).scheme.lower() in schemes:
                    return value
            except Exception:
                pass
        return None

    return find({'postgres', 'postgresql'}), find({'mongodb'}), find({'redis', 'rediss'})


def test_adversarial_corpus_verification():
    """
    Tests the /app/verify_manifest.py script against the clean and evil corpora.
    Ensures 100% of clean files are VALID and 100% of evil files are INVALID.
    """
    script_path = "/app/verify_manifest.py"
    clean_corpus_path = "/home/user/corpus/clean"
    evil_corpus_path = "/home/user/corpus/evil"

    assert os.path.isfile(script_path), f"The script {script_path} does not exist."

    clean_files = glob.glob(os.path.join(clean_corpus_path, "*.json"))
    evil_files = glob.glob(os.path.join(evil_corpus_path, "*.json"))

    assert len(clean_files) > 0, f"No clean corpus files found in {clean_corpus_path}"
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_corpus_path}"

    clean_failed = []
    evil_failed = []

    for filepath in clean_files:
        result = subprocess.run(
            ["python3", script_path, filepath],
            capture_output=True,
            text=True,
            timeout=10
        )
        output = result.stdout.strip()
        if output != "VALID":
            clean_failed.append(os.path.basename(filepath))

    for filepath in evil_files:
        result = subprocess.run(
            ["python3", script_path, filepath],
            capture_output=True,
            text=True,
            timeout=10
        )
        output = result.stdout.strip()
        if output != "INVALID":
            evil_failed.append(os.path.basename(filepath))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_manifest_verifier_on_fresh_mixed_corpus():
    script = '/app/verify_manifest.py'
    assert os.path.isfile(script)

    token = secrets.token_hex(6)
    a, b, c, d = [f'{token}_{x}' for x in 'abcd']
    cases = [
        ({'schedule_id': 'SCH-0000', 'nodes': [a, b, c, d],
          'edges': [[a, b], [a, c], [c, d]],
          'metadata': {'kind': 'full', 'details': {'owner': token}}}, 'VALID'),
        ({'schedule_id': 'SCH-9876', 'nodes': [a, b, c], 'edges': [],
          'metadata': {'parts': [{'name': a}, {'name': b}]}}, 'VALID'),
        ({'schedule_id': 'SCH-3141', 'nodes': [a, b, c],
          'edges': [[a, b], [b, c], [c, a]], 'metadata': {'kind': 'full'}}, 'INVALID'),
        ({'schedule_id': 'SCH-2718', 'nodes': [a], 'edges': [[a, a]],
          'metadata': {'kind': 'incremental'}}, 'INVALID'),
        ({'schedule_id': f'BAD-{secrets.randbelow(9000) + 1000}', 'nodes': [a, b],
          'edges': [[a, b]], 'metadata': {'kind': 'full'}}, 'INVALID'),
        ({'schedule_id': 'SCH-12345', 'nodes': [a, b], 'edges': [[a, b]],
          'metadata': {'kind': 'full'}}, 'INVALID'),
        ({'schedule_id': 'xSCH-1234', 'nodes': [a, b], 'edges': [[a, b]],
          'metadata': {'kind': 'full'}}, 'INVALID'),
        ({'schedule_id': 'SCH-4242', 'nodes': [a, b], 'edges': [[a, b]],
          'metadata': {'details': {'$where': 'return true'}}}, 'INVALID'),
        ({'schedule_id': 'SCH-5151', 'nodes': [a, b], 'edges': [[a, b]],
          'metadata': {'parts': [{'ok': 1}, {'$gt': 0}]}}, 'INVALID'),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix='manifest_checks_') as directory:
        for document, expected in cases:
            path = os.path.join(directory, secrets.token_hex(10) + '.json')
            with open(path, 'w', encoding='utf-8') as handle:
                json.dump(document, handle)
            result = subprocess.run(
                ['python3', script, path], capture_output=True, text=True, timeout=10
            )
            assert result.returncode == 0
            assert result.stderr == ''
            assert result.stdout in (expected, expected + '\n')


def test_part1_configuration_and_implementation():
    query_path = '/app/query_lineage.py'
    env_path = '/app/.env'
    assert os.path.isfile(query_path)
    assert os.path.isfile(env_path)

    pg_url, mongo_url, redis_url = _service_urls()
    assert pg_url, '.env must contain a PostgreSQL connection string'
    assert mongo_url, '.env must contain a MongoDB connection string'
    assert redis_url, '.env must contain a Redis connection string'

    for url, port in ((pg_url, 5432), (mongo_url, 27017), (redis_url, 6379)):
        parsed = urlparse(url)
        assert parsed.hostname in {'localhost', '127.0.0.1', '::1'}
        assert parsed.port == port
    assert urlparse(pg_url).path.rstrip('/') == '/backups'
    assert urlparse(mongo_url).path.rstrip('/') == '/backups'

    with open(query_path, encoding='utf-8') as handle:
        source = handle.read()
    tree = ast.parse(source, filename=query_path)

    sql_strings = [
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
        and re.search(r'\bselect\b', node.value, re.I)
        and re.search(r'\bschedules\b', node.value, re.I)
        and re.search(r'\bbackup_runs\b', node.value, re.I)
    ]
    assert sql_strings, 'No schedules/backup_runs SELECT query was found'

    proper_join = False
    for sql in sql_strings:
        normalized = ' '.join(sql.split())
        match = re.search(
            r'\bfrom\s+schedules(?:\s+(?:as\s+)?(?!join\b)(\w+))?\s+'
            r'(?:inner\s+)?join\s+backup_runs(?:\s+(?:as\s+)?(?!on\b)(\w+))?\s+'
            r'on\s+(.+)', normalized, re.I
        )
        if not match:
            continue
        schedule_alias = (match.group(1) or 'schedules').lower()
        run_alias = (match.group(2) or 'backup_runs').lower()
        on_clause = re.split(r'\bwhere\b|\bgroup\s+by\b|\border\s+by\b|\blimit\b', match.group(3), 1, flags=re.I)[0]
        equalities = re.findall(r'(\w+)\.schedule_id\s*=\s*(\w+)\.schedule_id', on_clause, re.I)
        if any({left.lower(), right.lower()} == {schedule_alias, run_alias} for left, right in equalities):
            proper_join = True
            break
    assert proper_join, 'SQL must explicitly JOIN schedules and backup_runs on their schedule_id columns'

    aggregate_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
        and node.func.attr == 'aggregate'
    ]
    assert aggregate_calls, 'MongoDB backup logs must be aggregated'
    assert any(
        '$group' in {n.value for n in ast.walk(call) if isinstance(n, ast.Constant) and isinstance(n.value, str)}
        and '$run_id' in {n.value for n in ast.walk(call) if isinstance(n, ast.Constant) and isinstance(n.value, str)}
        for call in aggregate_calls
    ), 'The MongoDB aggregation must group by $run_id'

    index_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
        and node.func.attr == 'create_index'
    ]
    assert index_calls, 'The pipeline must create a MongoDB index'
    assert any(
        'run_id' in {n.value for n in ast.walk(call) if isinstance(n, ast.Constant) and isinstance(n.value, str)}
        for call in index_calls
    ), 'The created MongoDB index must cover run_id'

    pg = psycopg2.connect(pg_url)
    pg.close()
    mongo = MongoClient(mongo_url, serverSelectionTimeoutMS=3000)
    assert mongo.admin.command('ping')['ok'] == 1
    mongo.close()
    assert redis.Redis.from_url(redis_url, socket_connect_timeout=3).ping()


def test_query_pipeline_executes_real_aggregation_and_creates_index():
    pg_url, mongo_url, redis_url = _service_urls()
    assert pg_url and mongo_url and redis_url

    client = MongoClient(mongo_url, serverSelectionTimeoutMS=3000)
    db = client.get_default_database()
    assert db.name == 'backups'
    collection = db.backup_logs
    collection.delete_many({})
    collection.insert_many([
        {'run_id': 'RUN-A', 'message': 'started'},
        {'run_id': 'RUN-A', 'message': 'finished'},
        {'run_id': 'RUN-B', 'message': 'finished'},
    ])
    for name in list(collection.index_information()):
        if name != '_id_':
            collection.drop_index(name)

    db.command('profile', 0)
    try:
        db.system.profile.drop()
    except Exception:
        pass
    db.command('profile', 2)
    try:
        result = subprocess.run(
            ['python3', '/app/query_lineage.py'], cwd='/app',
            capture_output=True, text=True, timeout=30
        )
    finally:
        db.command('profile', 0)

    assert result.returncode == 0, result.stdout + result.stderr
    indexes = collection.index_information()
    assert any(info.get('key') == [('run_id', 1)] for info in indexes.values()), \
        'query_lineage.py did not create the required ascending run_id index'
    assert db.system.profile.count_documents({'command.aggregate': 'backup_logs'}) > 0, \
        'query_lineage.py did not execute an aggregation on backup_logs'
    client.close()
TEST_EOF

prepare_services() {
    service postgresql start >/dev/null 2>&1 || return 1
    sudo -u postgres psql -v ON_ERROR_STOP=1 >/dev/null <<'SQL' || return 1
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dbre') THEN
    CREATE ROLE dbre LOGIN PASSWORD 'dbre_pass';
  ELSE
    ALTER ROLE dbre WITH LOGIN PASSWORD 'dbre_pass';
  END IF;
END
$$;
SQL
    sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='backups'" | grep -q 1 || sudo -u postgres createdb -O dbre backups || return 1
    sudo -u postgres psql -v ON_ERROR_STOP=1 -d backups >/dev/null <<'SQL' || return 1
DROP TABLE IF EXISTS backup_runs;
DROP TABLE IF EXISTS schedules;
CREATE TABLE schedules (
  schedule_id text PRIMARY KEY,
  schedule_name text,
  name text
);
CREATE TABLE backup_runs (
  run_id text PRIMARY KEY,
  schedule_id text REFERENCES schedules(schedule_id),
  status text
);
INSERT INTO schedules VALUES
  ('SCH-1001', 'daily', 'daily'),
  ('SCH-1002', 'weekly', 'weekly');
INSERT INTO backup_runs VALUES
  ('RUN-A', 'SCH-1001', 'complete'),
  ('RUN-B', 'SCH-1002', 'complete'),
  ('RUN-C', 'SCH-1001', 'complete');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO dbre;
SQL

    python3 - <<'PY' >/dev/null 2>&1
from pymongo import MongoClient
MongoClient('mongodb://localhost:27017', serverSelectionTimeoutMS=1000).admin.command('ping')
PY
    if [ $? -ne 0 ]; then
        mkdir -p /data/db /var/log
        chown -R mongodb:mongodb /data/db
        mongod --fork --logpath /var/log/mongodb.log --dbpath /data/db >/dev/null 2>&1 || return 1
    fi

    redis-cli ping >/dev/null 2>&1 || redis-server --daemonize yes >/dev/null 2>&1 || return 1
    return 0
}

if prepare_services && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
