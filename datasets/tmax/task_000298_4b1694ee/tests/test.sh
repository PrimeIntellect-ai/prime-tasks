#!/bin/bash
mkdir -p /logs/verifier

service postgresql start >/dev/null 2>&1 || true
service redis-server start >/dev/null 2>&1 || true
sleep 2

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import random
import subprocess

import psycopg2
import redis

AGENT_SCRIPT = "/home/user/backup_extractor.py"
NODE_COUNT = 1000


def install_hidden_fixture():
    rng = random.Random(918273)
    transient = {node_id for node_id in range(1, NODE_COUNT + 1) if rng.randrange(9) == 0}

    edges = []
    adjacency = collections.defaultdict(list)
    for source in range(1, NODE_COUNT + 1):
        targets = {
            source % NODE_COUNT + 1,
            (source + 96) % NODE_COUNT + 1,
            rng.randint(1, NODE_COUNT),
        }
        for target in sorted(targets):
            weight = rng.random() * 10.0
            edges.append((source, target, weight))
            adjacency[source].append(target)

    conn = psycopg2.connect(
        host="localhost", port=5432, dbname="graphdb",
        user="postgres", password="postgres"
    )
    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            cur.execute("DROP TABLE IF EXISTS edges")
            cur.execute("DROP TABLE IF EXISTS nodes")
            cur.execute("""
                CREATE TABLE nodes (
                    id INT PRIMARY KEY,
                    type VARCHAR NOT NULL,
                    data JSONB NOT NULL
                )
            """)
            cur.execute("""
                CREATE TABLE edges (
                    source_id INT NOT NULL,
                    target_id INT NOT NULL,
                    weight FLOAT NOT NULL
                )
            """)
            cur.executemany(
                "INSERT INTO nodes (id, type, data) VALUES (%s, %s, %s::jsonb)",
                [
                    (node_id, "transient" if node_id in transient else "entity",
                     json.dumps({"id": node_id, "fixture": "verification"}))
                    for node_id in range(1, NODE_COUNT + 1)
                ],
            )
            cur.executemany(
                "INSERT INTO edges (source_id, target_id, weight) VALUES (%s, %s, %s)",
                edges,
            )
            cur.execute("CREATE INDEX edges_source_idx ON edges (source_id)")
    finally:
        conn.close()

    return transient, adjacency


def expected_nodes(start_node, max_depth, transient, adjacency):
    distance = {start_node: 0}
    frontier = [start_node]
    for depth in range(1, max_depth + 1):
        next_frontier = []
        for source in frontier:
            for target in adjacency.get(source, ()):
                if target not in distance:
                    distance[target] = depth
                    next_frontier.append(target)
        frontier = next_frontier
        if not frontier:
            break

    return [
        node_id
        for node_id, _ in sorted(distance.items(), key=lambda item: (item[1], item[0]))
        if node_id not in transient
    ]


def test_fuzz_equivalence_and_redis_pipeline():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script is not executable: {AGENT_SCRIPT}"

    transient, adjacency = install_hidden_fixture()
    redis_client = redis.Redis(host="localhost", port=6379, db=0)
    redis_client.ping()

    random.seed(42)
    for _ in range(50):
        start_node = random.randint(1, 1000)
        max_depth = random.randint(1, 5)
        expected = expected_nodes(start_node, max_depth, transient, adjacency)
        expected_stdout = json.dumps(expected)
        key = f"backup:path:{start_node}"
        redis_client.delete(key)

        proc = subprocess.run(
            ["python3", AGENT_SCRIPT, "--start-node", str(start_node),
             "--max-depth", str(max_depth)],
            capture_output=True,
            text=True,
        )

        assert proc.returncode == 0, (
            f"Agent script failed on input --start-node {start_node} "
            f"--max-depth {max_depth}.\nStderr: {proc.stderr}"
        )
        assert proc.stdout.strip() == expected_stdout, (
            f"Mismatch on input --start-node {start_node} --max-depth {max_depth}.\n"
            f"Agent output: {proc.stdout.strip()}\nExpected output: {expected_stdout}"
        )

        stored = redis_client.get(key)
        assert stored is not None, f"Redis key {key} was not written"
        try:
            stored_value = json.loads(stored.decode("utf-8"))
        except Exception as exc:
            raise AssertionError(f"Redis key {key} does not contain valid JSON: {stored!r}") from exc
        assert stored_value == expected, (
            f"Redis value mismatch for {key}. Stored: {stored_value}; Expected: {expected}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
