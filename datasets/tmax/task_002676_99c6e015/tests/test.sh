#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import math
import os
import sqlite3
import subprocess

import jsonschema

HOME = "/home/user"
DB_PATH = os.path.join(HOME, "backups.db")
TOPOLOGY_PATH = os.path.join(HOME, "network_topology.json")
SCHEMA_PATH = os.path.join(HOME, "schema.json")
PLAN_PATH = os.path.join(HOME, "transfer_plan.json")
TARGET = "ap-northeast-1"
BACKUP_NAME = "auth_db_snapshot_2023"

BASE_SCHEMA = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "properties": {
        "backup_name": {"type": "string"},
        "path": {"type": "array", "items": {"type": "string"}},
        "total_time_ms": {"type": "number"},
    },
    "required": ["backup_name", "path", "total_time_ms"],
    "additionalProperties": False,
}

ORIGINAL = {
    "size_mb": 5000.0,
    "current_node": "us-east-1",
    "edges": [
        {"source": "us-east-1", "target": "eu-west-1", "latency_ms": 80, "bandwidth_mbps": 250},
        {"source": "us-east-1", "target": "us-west-2", "latency_ms": 60, "bandwidth_mbps": 500},
        {"source": "us-west-2", "target": "ap-northeast-1", "latency_ms": 120, "bandwidth_mbps": 100},
        {"source": "eu-west-1", "target": "ap-northeast-1", "latency_ms": 150, "bandwidth_mbps": 300},
        {"source": "us-east-1", "target": "ap-northeast-1", "latency_ms": 200, "bandwidth_mbps": 50},
    ],
}

CASES = [
    ORIGINAL,
    {
        "size_mb": 120.0,
        "current_node": "node-alpha",
        "edges": [
            {"source": "node-alpha", "target": "node-beta", "latency_ms": 10, "bandwidth_mbps": 60},
            {"source": "node-beta", "target": TARGET, "latency_ms": 20, "bandwidth_mbps": 120},
            {"source": "node-alpha", "target": TARGET, "latency_ms": 5, "bandwidth_mbps": 20},
            {"source": "node-alpha", "target": "dead-end", "latency_ms": 1, "bandwidth_mbps": 1000},
        ],
    },
    {
        "size_mb": 900.0,
        "current_node": "source-two",
        "edges": [
            {"source": "source-two", "target": "fast-hop", "latency_ms": 5, "bandwidth_mbps": 900},
            {"source": "fast-hop", "target": TARGET, "latency_ms": 5, "bandwidth_mbps": 900},
            {"source": "source-two", "target": "slow-hop", "latency_ms": 1, "bandwidth_mbps": 100},
            {"source": "slow-hop", "target": TARGET, "latency_ms": 1, "bandwidth_mbps": 100},
            {"source": "source-two", "target": TARGET, "latency_ms": 50, "bandwidth_mbps": 300},
        ],
    },
]


def remove_db_sidecars():
    for suffix in ("", "-journal", "-wal", "-shm"):
        path = DB_PATH + suffix
        if os.path.lexists(path):
            os.remove(path)


def install_fixture(case, schema=None):
    remove_db_sidecars()
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("CREATE TABLE backups (id INTEGER PRIMARY KEY, name TEXT, size_mb REAL, current_node TEXT)")
        conn.execute(
            "INSERT INTO backups (name, size_mb, current_node) VALUES (?, ?, ?)",
            (BACKUP_NAME, case["size_mb"], case["current_node"]),
        )
        conn.execute(
            "INSERT INTO backups (name, size_mb, current_node) VALUES (?, ?, ?)",
            ("unrelated_backup", 42.0, "unrelated-node"),
        )
        conn.commit()
    finally:
        conn.close()

    with open(TOPOLOGY_PATH, "w") as f:
        json.dump({"edges": case["edges"]}, f)
    with open(SCHEMA_PATH, "w") as f:
        json.dump(BASE_SCHEMA if schema is None else schema, f)


def expected_from_installed_inputs():
    conn = sqlite3.connect(DB_PATH)
    try:
        row = conn.execute(
            "SELECT size_mb, current_node FROM backups WHERE name = ?",
            (BACKUP_NAME,),
        ).fetchone()
    finally:
        conn.close()
    assert row is not None
    size_mb, source = row

    with open(TOPOLOGY_PATH) as f:
        edges = json.load(f)["edges"]

    graph = {}
    for edge in edges:
        weight = float(edge["latency_ms"]) + (float(size_mb) / float(edge["bandwidth_mbps"])) * 1000.0
        graph.setdefault(edge["source"], []).append((edge["target"], weight))

    queue = [(0.0, source, [source])]
    best = {source: 0.0}
    while queue:
        total, node, path = heapq.heappop(queue)
        if total > best.get(node, float("inf")):
            continue
        if node == TARGET:
            return path, total
        for neighbor, weight in graph.get(node, []):
            candidate = total + weight
            if candidate < best.get(neighbor, float("inf")):
                best[neighbor] = candidate
                heapq.heappush(queue, (candidate, neighbor, path + [neighbor]))
    raise AssertionError("Verifier fixture unexpectedly has no route to the target")


def candidate_scripts():
    excluded = {DB_PATH, TOPOLOGY_PATH, SCHEMA_PATH, PLAN_PATH}
    found = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {"__pycache__", ".cache", ".local"}]
        for name in files:
            path = os.path.join(root, name)
            if path in excluded or not os.path.isfile(path):
                continue
            try:
                with open(path, "rb") as f:
                    first_line = f.readline(256)
            except OSError:
                continue
            if name.endswith(".py") or (first_line.startswith(b"#!") and b"python" in first_line.lower()):
                found.append(path)
    return sorted(found)


def execute_script(script):
    if os.path.lexists(PLAN_PATH):
        os.remove(PLAN_PATH)
    return subprocess.run(
        ["python3", script],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )


def check_positive_case(script, case, original=False):
    install_fixture(case)
    expected_path, expected_time = expected_from_installed_inputs()
    result = execute_script(script)
    assert result.returncode == 0, "script exited nonzero: " + result.stderr[-1000:]
    assert os.path.isfile(PLAN_PATH), f"Expected output file {PLAN_PATH} is missing. The script did not generate it."

    try:
        with open(PLAN_PATH) as f:
            plan = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"The file {PLAN_PATH} does not contain valid JSON: {exc}")

    assert isinstance(plan, dict), "The top-level JSON structure must be an object (dictionary)."
    assert "backup_name" in plan, "Missing 'backup_name' in the transfer plan."
    assert "path" in plan, "Missing 'path' in the transfer plan."
    assert "total_time_ms" in plan, "Missing 'total_time_ms' in the transfer plan."

    with open(SCHEMA_PATH) as f:
        active_schema = json.load(f)
    jsonschema.validate(plan, active_schema)

    assert plan["backup_name"] == BACKUP_NAME
    assert plan["path"] == expected_path, f"Expected path {expected_path}, got {plan.get('path')}"
    assert isinstance(plan["total_time_ms"], (int, float)) and not isinstance(plan["total_time_ms"], bool)
    assert math.isclose(plan["total_time_ms"], expected_time, rel_tol=1e-9, abs_tol=0.1), (
        f"Expected total_time_ms approximately {expected_time}, got {plan.get('total_time_ms')}"
    )

    # Preserve the original verifier's exact fixture assertions.
    if original:
        assert plan["path"] == ["us-east-1", "eu-west-1", "ap-northeast-1"]
        assert math.isclose(plan["total_time_ms"], 36896.666666666664, abs_tol=0.1)


def check_schema_is_actually_enforced(script):
    impossible_schema = dict(BASE_SCHEMA)
    impossible_schema["not"] = {}
    install_fixture(ORIGINAL, impossible_schema)
    result = execute_script(script)
    # A script that validates cannot successfully leave a transfer plan under a
    # schema which rejects every possible JSON value.
    assert result.returncode != 0 or not os.path.isfile(PLAN_PATH), (
        "script reported success and wrote a plan despite an impossible schema"
    )


def test_executable_solution_script_generates_and_validates_plan():
    scripts = candidate_scripts()
    assert scripts, "No Python script was found under /home/user"

    failures = []
    winner = None
    try:
        for script in scripts:
            try:
                for index, case in enumerate(CASES):
                    check_positive_case(script, case, original=(index == 0))
                check_schema_is_actually_enforced(script)
                winner = script
                break
            except (AssertionError, jsonschema.ValidationError, subprocess.TimeoutExpired, OSError, ValueError) as exc:
                failures.append(f"{script}: {exc}")

        assert winner is not None, "No submitted Python script passed execution tests:\n" + "\n".join(failures)

        # Leave the requested plan generated from the original incident inputs.
        check_positive_case(winner, ORIGINAL, original=True)
    finally:
        install_fixture(ORIGINAL)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
