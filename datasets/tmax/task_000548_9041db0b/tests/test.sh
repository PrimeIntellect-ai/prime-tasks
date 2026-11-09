#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_instrument
cat << 'PY_EOF' > /tmp/verifier_instrument/sitecustomize.py
import json
import os
import psycopg2

_real_connect = psycopg2.connect
_log_path = os.environ.get("VERIFIER_SQL_LOG")

class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, query, params=None):
        if _log_path:
            try:
                with open(_log_path, "a", encoding="utf-8") as f:
                    f.write(json.dumps({"pid": os.getpid(), "query": str(query)}) + "\n")
            except Exception:
                pass
        if params is None:
            return self._cursor.execute(query)
        return self._cursor.execute(query, params)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

    def __iter__(self):
        return iter(self._cursor)

    def __enter__(self):
        self._cursor.__enter__()
        return self

    def __exit__(self, *args):
        return self._cursor.__exit__(*args)

class ConnectionProxy:
    def __init__(self, connection):
        self._connection = connection

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def __getattr__(self, name):
        return getattr(self._connection, name)

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

def instrumented_connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

psycopg2.connect = instrumented_connect
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import filecmp
import json
import os
import random
import stat
import subprocess

import psycopg2
import pytest
import redis
from dotenv import dotenv_values

ORACLE_PATH = "/app/oracle_query"
AGENT_SCRIPT = "/home/user/dataset_query.py"
CONFIG_PATH = "/home/user/config.env"
SQL_LOG = "/tmp/verifier_sql.log"


def load_and_check_config():
    assert os.path.isfile(CONFIG_PATH), f"Configuration missing at {CONFIG_PATH}"
    config = dotenv_values(CONFIG_PATH)
    expected = {
        "DB_PORT": "5432",
        "DB_NAME": "research_db",
        "DB_USER": "researcher",
        "DB_PASS": "password123",
        "REDIS_PORT": "6379",
    }
    for key, value in expected.items():
        assert config.get(key) == value, f"Incorrect {key} in config.env"
    assert config.get("DB_HOST") in {"localhost", "127.0.0.1"}, "Incorrect DB_HOST"
    assert config.get("REDIS_HOST") in {"localhost", "127.0.0.1"}, "Incorrect REDIS_HOST"
    return config


def load_graph(conn):
    with conn.cursor() as cursor:
        cursor.execute("SELECT id, is_active FROM datasets")
        active = {row[0] for row in cursor.fetchall() if row[1]}
        cursor.execute("SELECT source_id, target_id FROM dataset_dependencies")
        edges = {}
        for source, target in cursor.fetchall():
            edges.setdefault(source, set()).add(target)
    return active, edges


def derive_expected(dataset_id, max_depth, limit, offset, active, edges):
    reached_pairs = {(dataset_id, 0)}
    frontier = {dataset_id}
    for depth in range(max_depth):
        next_frontier = set()
        for node in frontier:
            next_frontier.update(edges.get(node, ()))
        for node in next_frontier:
            reached_pairs.add((node, depth + 1))
        frontier = next_frontier
    ids = sorted({node for node, _depth in reached_pairs if node in active})
    return ids[offset:offset + limit]


def test_final_state():
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    mode = os.stat(AGENT_SCRIPT, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), "dataset_query.py must be a regular source file"
    assert not os.path.islink(AGENT_SCRIPT), "dataset_query.py must not be a symlink"
    assert not filecmp.cmp(AGENT_SCRIPT, ORACLE_PATH, shallow=False), "Submission must not be a copy of the oracle"

    with open(AGENT_SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    ast.parse(source, filename=AGENT_SCRIPT)
    assert "oracle_query" not in source, "dataset_query.py must implement the query rather than invoke the oracle"

    config = load_and_check_config()

    try:
        conn = psycopg2.connect(
            host=config["DB_HOST"],
            port=int(config["DB_PORT"]),
            dbname=config["DB_NAME"],
            user=config["DB_USER"],
            password=config["DB_PASS"],
            connect_timeout=3,
        )
    except Exception as exc:
        pytest.fail(f"PostgreSQL is not reachable using config.env: {exc}")

    try:
        active, edges = load_graph(conn)
    finally:
        conn.close()

    try:
        cache = redis.Redis(
            host=config["REDIS_HOST"],
            port=int(config["REDIS_PORT"]),
            socket_connect_timeout=3,
            socket_timeout=3,
        )
        assert cache.ping() is True
    except Exception as exc:
        pytest.fail(f"Redis is not reachable using config.env: {exc}")

    try:
        os.remove(SQL_LOG)
    except FileNotFoundError:
        pass

    child_env = os.environ.copy()
    child_env["VERIFIER_SQL_LOG"] = SQL_LOG
    child_env["PYTHONPATH"] = "/tmp/verifier_instrument" + (
        os.pathsep + child_env["PYTHONPATH"] if child_env.get("PYTHONPATH") else ""
    )

    random.seed(42)
    cases = []
    for _ in range(50):
        cases.append((
            random.randint(1, 50),
            random.randint(1, 4),
            random.randint(5, 20),
            random.randint(0, 10),
        ))

    for dataset_id, max_depth, limit, offset in cases:
        args = [
            "--dataset-id", str(dataset_id),
            "--max-depth", str(max_depth),
            "--limit", str(limit),
            "--offset", str(offset),
        ]

        try:
            oracle_res = subprocess.run(
                [ORACLE_PATH] + args,
                capture_output=True,
                text=True,
                check=True,
                timeout=20,
            )
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            pytest.fail(f"Oracle failed on input {args}: {exc}")

        try:
            agent_res = subprocess.run(
                ["python3", AGENT_SCRIPT] + args,
                capture_output=True,
                text=True,
                env=child_env,
                timeout=20,
            )
        except Exception as exc:
            pytest.fail(f"Agent script failed to execute on input {args}: {exc}")

        oracle_out = oracle_res.stdout.strip()
        agent_out = agent_res.stdout.strip()
        expected_out = json.dumps(
            derive_expected(dataset_id, max_depth, limit, offset, active, edges)
        )

        assert agent_res.returncode == 0, (
            f"Agent script returned non-zero on input {args}. Stderr: {agent_res.stderr}"
        )
        assert oracle_out == expected_out, (
            f"Reference mismatch on input {args}: oracle={oracle_out}, derived={expected_out}"
        )
        assert agent_out == oracle_out, (
            f"Mismatch on input {args}. Expected (Oracle): {oracle_out}; Got: {agent_out}"
        )
        assert agent_out == expected_out, (
            f"Mismatch against independently derived result on input {args}"
        )

    assert os.path.isfile(SQL_LOG), "The submitted script did not execute SQL through psycopg2"
    qualifying_queries = 0
    with open(SQL_LOG, "r", encoding="utf-8") as f:
        for line in f:
            record = json.loads(line)
            normalized = " ".join(record["query"].upper().split())
            required = (
                "WITH RECURSIVE",
                "DATASET_DEPENDENCIES",
                "JOIN",
                "DEPTH",
                "IS_ACTIVE",
                "ORDER BY",
                "LIMIT",
                "OFFSET",
            )
            if all(token in normalized for token in required):
                qualifying_queries += 1

    assert qualifying_queries >= len(cases), (
        "dataset_query.py must execute the recursive dependency SQL itself for every request"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
