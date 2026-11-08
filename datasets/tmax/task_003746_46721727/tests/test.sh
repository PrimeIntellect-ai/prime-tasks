#!/bin/bash
set +e
mkdir -p /logs/verifier

/app/start_services.sh >/tmp/verifier-services.log 2>&1
service_status=$?

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import heapq
import json
import os
import re
import secrets
import subprocess
import tempfile
import time
from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone

import psycopg2
import pytest

AGENT_SCRIPT = "/home/user/classifier.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def run_classifier(file_path):
    result = subprocess.run(
        ["python3", AGENT_SCRIPT, file_path],
        capture_output=True,
        text=True,
        timeout=5
    )
    return result.stdout.strip()


def test_classifier_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"


def test_clean_corpus():
    if not os.path.isdir(CLEAN_CORPUS_DIR):
        pytest.fail(f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}")

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    assert clean_files, "No clean corpus files found."

    failed_files = []
    for filepath in clean_files:
        output = run_classifier(filepath)
        if output != "CLEAN":
            failed_files.append((os.path.basename(filepath), output))

    if failed_files:
        details = ", ".join([f"{f} (got '{o}')" for f, o in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected incorrectly: {details}")


def test_evil_corpus():
    if not os.path.isdir(EVIL_CORPUS_DIR):
        pytest.fail(f"Evil corpus directory missing: {EVIL_CORPUS_DIR}")

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    assert evil_files, "No evil corpus files found."

    failed_files = []
    for filepath in evil_files:
        output = run_classifier(filepath)
        if output != "EVIL":
            failed_files.append((os.path.basename(filepath), output))

    if failed_files:
        details = ", ".join([f"{f} (got '{o}')" for f, o in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed incorrectly: {details}")


def parse_timestamp(value):
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    dt = datetime.fromisoformat(value)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def expected_result(events, edges):
    graph = defaultdict(list)
    for source, dest, cost in edges:
        graph[source].append((dest, int(cost)))

    def shortest_path(source, target):
        if source == target:
            return 0
        queue = [(0, source)]
        best = {source: 0}
        while queue:
            distance, node = heapq.heappop(queue)
            if distance != best[node]:
                continue
            if node == target:
                return distance
            for neighbor, edge_cost in graph.get(node, []):
                candidate = distance + edge_cost
                if candidate < best.get(neighbor, float("inf")):
                    best[neighbor] = candidate
                    heapq.heappush(queue, (candidate, neighbor))
        return None

    for event in events:
        distance = shortest_path(event["source"], event["target"])
        if distance is None or distance > 15:
            return "EVIL"

    by_user = defaultdict(list)
    for event in events:
        by_user[event["user_id"]].append(parse_timestamp(event["timestamp"]))
    for timestamps in by_user.values():
        timestamps.sort()
        window = deque()
        for timestamp in timestamps:
            window.append(timestamp)
            while timestamp - window[0] > timedelta(minutes=10):
                window.popleft()
            if len(window) > 3:
                return "EVIL"
    return "CLEAN"


def log_offsets():
    paths = glob.glob("/var/log/postgresql/*.log")
    assert paths, "PostgreSQL log file was not found"
    return {path: os.path.getsize(path) for path in paths}


def logs_since(offsets):
    time.sleep(0.2)
    output = []
    for path in glob.glob("/var/log/postgresql/*.log"):
        start = offsets.get(path, 0)
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            handle.seek(start)
            output.append(handle.read())
    return "\n".join(output)


def event(ts, user, source, target):
    return {
        "timestamp": ts.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "user_id": user,
        "source": source,
        "target": target,
    }


def test_randomized_inputs_use_postgresql_graph_and_sql_analytics():
    token = secrets.token_hex(8)
    nodes = {name: f"audit_{token}_{name}" for name in (
        "c0", "c1", "c2", "h0", "h1", "h2", "iso", "a0", "a1", "a2", "a3"
    )}

    generated_edges = [
        (nodes["c0"], nodes["c1"], 7),
        (nodes["c1"], nodes["c2"], 8),
        (nodes["h0"], nodes["h1"], 8),
        (nodes["h1"], nodes["h2"], 8),
        (nodes["a0"], nodes["a1"], 12),
        (nodes["a1"], nodes["a3"], 12),
        (nodes["a0"], nodes["a2"], 4),
        (nodes["a2"], nodes["a3"], 5),
    ]

    conn = psycopg2.connect(host="127.0.0.1", port=5432, dbname="audit", user="postgres", password="password")
    conn.autocommit = True
    with conn.cursor() as cursor:
        cursor.executemany(
            "INSERT INTO network_graph (source_node, dest_node, cost) VALUES (%s, %s, %s)",
            generated_edges,
        )
        cursor.execute("SELECT source_node, dest_node, cost FROM network_graph")
        all_edges = cursor.fetchall()
        cursor.execute("ALTER SYSTEM SET log_statement = 'all'")
        cursor.execute("SELECT pg_reload_conf()")
    conn.close()
    time.sleep(0.2)

    base = datetime(2026, 1, 1, 12, 0, tzinfo=timezone.utc)
    user1 = f"user_{secrets.token_hex(5)}"
    user2 = f"user_{secrets.token_hex(5)}"

    cases = [
        [event(base, user1, nodes["c0"], nodes["c2"])],
        [event(base, user1, nodes["h0"], nodes["h2"])],
        [event(base, user1, nodes["iso"], nodes["c0"])],
        [event(base + timedelta(minutes=i * 3), user1, nodes["c0"], nodes["c2"]) for i in range(4)],
        [event(base + timedelta(minutes=i * 4), user1, nodes["c0"], nodes["c2"]) for i in range(4)],
        [
            event(base + timedelta(minutes=8), user1, nodes["c0"], nodes["c2"]),
            event(base, user2, nodes["a0"], nodes["a3"]),
            event(base, user1, nodes["a0"], nodes["a3"]),
            event(base + timedelta(minutes=4), user2, nodes["c0"], nodes["c2"]),
            event(base + timedelta(minutes=4), user1, nodes["c0"], nodes["c2"]),
            event(base + timedelta(minutes=8), user2, nodes["a0"], nodes["a3"]),
        ],
        [event(base, user1, nodes["c2"], nodes["c0"])],
        [event(base, user1, nodes["a0"], nodes["a3"])],
    ]

    expected = [expected_result(case, all_edges) for case in cases]
    assert "CLEAN" in expected and "EVIL" in expected

    offsets = log_offsets()
    with tempfile.TemporaryDirectory(prefix=f"audit-input-{token}-") as directory:
        for index, (events, answer) in enumerate(zip(cases, expected)):
            path = os.path.join(directory, f"sample-{secrets.token_hex(6)}-{index}.json")
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(events, handle)

            started = time.monotonic()
            result = subprocess.run(
                ["python3", AGENT_SCRIPT, path],
                capture_output=True,
                text=True,
                timeout=5,
            )
            elapsed = time.monotonic() - started
            assert result.returncode == 0, f"Classifier exited {result.returncode}: {result.stderr}"
            assert result.stdout == answer + "\n", f"Expected {answer}, got stdout {result.stdout!r}"
            assert elapsed < 2.0, f"Classifier took {elapsed:.3f}s for one file"

    sql_log = logs_since(offsets)
    assert re.search(r"\bwith\s+recursive\b", sql_log, re.IGNORECASE), "No recursive SQL query was executed"
    assert re.search(r"\bnetwork_graph\b", sql_log, re.IGNORECASE), "No SQL query accessed network_graph"
    assert re.search(r"\bcreate\s+(?:temporary|temp)\s+table\b", sql_log, re.IGNORECASE), "No temporary event table was created"
    assert re.search(r"\binsert\s+into\b", sql_log, re.IGNORECASE), "Events were not inserted using SQL"
    assert re.search(r"\bover\s*\(", sql_log, re.IGNORECASE), "No SQL window function was executed"
TEST_EOF

if [ "$service_status" -eq 0 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
