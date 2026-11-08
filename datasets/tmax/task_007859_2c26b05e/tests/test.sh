#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_etl_pipeline.py
import ast
import csv
import json
import math
import os
import re
import sqlite3
import subprocess
import sys
import uuid
from collections import Counter

import networkx as nx
import pytest
from pymongo import MongoClient

HOME = "/home/user"
SCRIPT = os.path.join(HOME, "etl_pipeline.py")
DB_PATH = os.path.join(HOME, "warehouse.db")
CSV_PATH = os.path.join(HOME, "result.csv")
HOOK_DIR = "/tmp/verifier_hooks"
HOOK_LOG = "/tmp/networkx_calls.log"


def recursive_has(obj, key, value=None):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == key and (value is None or v == value):
                return True
            if recursive_has(v, key, value):
                return True
    elif isinstance(obj, list):
        return any(recursive_has(v, key, value) for v in obj)
    return False


def install_networkx_hook():
    os.makedirs(HOOK_DIR, exist_ok=True)
    with open(os.path.join(HOOK_DIR, "sitecustomize.py"), "w") as f:
        f.write(r'''
import os
import sys
_seen = set()
_log = os.environ.get("VERIFIER_NX_LOG")
def _trace(frame, event, arg):
    if event == "call" and _log:
        filename = frame.f_code.co_filename.replace("\\", "/")
        name = frame.f_code.co_name
        marker = None
        if "/networkx/" in filename and name == "pagerank":
            marker = "pagerank"
        elif "/networkx/classes/digraph.py" in filename and name == "__init__":
            marker = "DiGraph"
        if marker and marker not in _seen:
            _seen.add(marker)
            try:
                with open(_log, "a") as out:
                    out.write(marker + "\n")
            except Exception:
                pass
    return _trace
sys.setprofile(_trace)
''')


def run_pipeline():
    assert os.path.isfile(SCRIPT), f"Required script {SCRIPT} is missing."
    assert os.path.getsize(SCRIPT) > 0, f"Required script {SCRIPT} is empty."
    for path in (DB_PATH, CSV_PATH, HOOK_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    install_networkx_hook()
    env = os.environ.copy()
    env["PYTHONPATH"] = HOOK_DIR + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["VERIFIER_NX_LOG"] = HOOK_LOG
    result = subprocess.run(
        [sys.executable, SCRIPT], cwd=HOME, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=90
    )
    assert result.returncode == 0, (
        f"etl_pipeline.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    calls = set()
    if os.path.exists(HOOK_LOG):
        with open(HOOK_LOG) as f:
            calls = {line.strip() for line in f if line.strip()}
    assert "DiGraph" in calls, "etl_pipeline.py did not construct a NetworkX DiGraph at runtime."
    assert "pagerank" in calls, "etl_pipeline.py did not call NetworkX PageRank at runtime."


def check_source_requirements():
    with open(SCRIPT, "r") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT)
    except SyntaxError as exc:
        pytest.fail(f"etl_pipeline.py is not valid Python: {exc}")

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                if isinstance(target, ast.Name):
                    assignments[target.id] = value

    def string_value(node, seen=None):
        seen = set() if seen is None else seen
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.Name) and node.id in assignments and node.id not in seen:
            return string_value(assignments[node.id], seen | {node.id})
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            left = string_value(node.left, seen)
            right = string_value(node.right, seen)
            if left is not None and right is not None:
                return left + right
        if isinstance(node, ast.JoinedStr):
            parts = []
            for item in node.values:
                if isinstance(item, ast.Constant) and isinstance(item.value, str):
                    parts.append(item.value)
                else:
                    parts.append("{}")
            return "".join(parts)
        return None

    parameterized_inserts = set()
    join_queries = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr not in {"execute", "executemany"} or not node.args:
            continue
        sql = string_value(node.args[0])
        if not sql:
            continue
        normalized = " ".join(sql.upper().split())
        match = re.search(r"INSERT\s+(?:OR\s+\w+\s+)?INTO\s+([A-Z_][A-Z0-9_]*)", normalized)
        if match and len(node.args) >= 2:
            parameterized_inserts.add(match.group(1).lower())
        if re.search(r"\bJOIN\b", normalized):
            join_queries.append(normalized)

    assert {"nodes", "edges"}.issubset(parameterized_inserts), (
        "Both nodes and edges must be loaded with parameterized execute/executemany SQL calls."
    )
    assert any(q.count("JOIN") >= 2 and "NODES" in q and "EDGES" in q for q in join_queries), (
        "etl_pipeline.py must execute the influential-transfer query using JOINs from edges to both node endpoints."
    )


def reset_profiler(db):
    db.command("profile", 0)
    try:
        db["system.profile"].drop()
    except Exception:
        pass
    db.command("profile", 2)


def assert_required_mongo_aggregation(db):
    entries = list(db["system.profile"].find({"op": "command", "command.aggregate": "transactions"}))
    assert entries, "No MongoDB aggregation command on fin_data.transactions was observed while running the script."
    valid = False
    for entry in entries:
        pipeline = entry.get("command", {}).get("pipeline", [])
        group_stages = [stage["$group"] for stage in pipeline if isinstance(stage, dict) and "$group" in stage]
        match_stages = [stage["$match"] for stage in pipeline if isinstance(stage, dict) and "$match" in stage]
        for group in group_stages:
            group_id = group.get("_id", {}) if isinstance(group, dict) else {}
            id_values = set(group_id.values()) if isinstance(group_id, dict) else set()
            sums_amount = any(isinstance(v, dict) and v.get("$sum") == "$amount" for v in group.values())
            if {"$sender", "$receiver"}.issubset(id_values) and sums_amount and any(recursive_has(m, "$gt", 50) for m in match_stages):
                valid = True
    assert valid, "Mongo aggregation must group by sender/receiver, sum amount, and apply a pipeline $match with $gt: 50."


def read_db():
    assert os.path.exists(DB_PATH), f"SQLite database {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    cur.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = {row["name"] for row in cur.fetchall()}
    assert "nodes" in tables, "Table 'nodes' is missing in warehouse.db"
    assert "edges" in tables, "Table 'edges' is missing in warehouse.db"
    cur.execute("SELECT sender, receiver, volume FROM edges")
    edges = [(row["sender"], row["receiver"], float(row["volume"])) for row in cur.fetchall()]
    cur.execute("SELECT node_id, pagerank FROM nodes")
    nodes = {row["node_id"]: float(row["pagerank"]) for row in cur.fetchall()}
    conn.close()
    return edges, nodes


def read_csv():
    assert os.path.exists(CSV_PATH), f"Result CSV {CSV_PATH} is missing."
    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["sender", "receiver", "volume", "combined_pagerank"], (
            f"CSV headers do not match. Got {reader.fieldnames}"
        )
        rows = list(reader)
    assert len(rows) == 1, f"Expected exactly 1 row in result.csv, got {len(rows)}"
    return rows[0]


def test_complete_etl_pipeline():
    # Preserve the original Mongo setup assertions.
    data_dir = "/home/user/mongo_data"
    log_file = "/home/user/mongo.log"
    assert os.path.exists(data_dir) and os.path.isdir(data_dir), f"MongoDB data directory {data_dir} is missing or not a directory."
    assert os.path.exists(log_file) and os.path.isfile(log_file), f"MongoDB log file {log_file} is missing or not a file."
    try:
        subprocess.check_output(["pgrep", "mongod"])
    except subprocess.CalledProcessError:
        pytest.fail("mongod process is not running.")

    client = MongoClient("mongodb://localhost:27017", serverSelectionTimeoutMS=5000)
    client.admin.command("ping")
    db = client["fin_data"]
    collection = db["transactions"]

    with open(os.path.join(HOME, "transactions.jsonl")) as f:
        original_docs = [json.loads(line) for line in f if line.strip()]
    actual_docs = list(collection.find({}, {"_id": 0}))
    canonical = lambda d: json.dumps(d, sort_keys=True, separators=(",", ":"))
    assert Counter(map(canonical, actual_docs)) == Counter(map(canonical, original_docs)), (
        "fin_data.transactions does not contain exactly the provided JSON Lines records."
    )

    check_source_requirements()

    # Execute the submitted artifact from a clean output state on the required input.
    reset_profiler(db)
    run_pipeline()
    assert_required_mongo_aggregation(db)

    edges, nodes = read_db()
    expected_edges = {
        ("A", "B", 70.0), ("B", "C", 100.0), ("C", "A", 80.0),
        ("D", "B", 200.0), ("A", "D", 300.0), ("D", "E", 60.0),
        ("E", "A", 70.0)
    }
    assert set(edges) == expected_edges, f"Edges in warehouse.db do not match expected filtered aggregation. Got {set(edges)}"
    assert set(nodes) == {"A", "B", "C", "D", "E"}, f"Nodes in warehouse.db do not match expected entities. Got {set(nodes)}"
    for node_id, pr in nodes.items():
        assert 0 < pr < 1, f"PageRank for node {node_id} is out of bounds: {pr}"

    row = read_csv()
    assert row["sender"] == "A", f"Expected sender 'A', got {row['sender']}"
    assert row["receiver"] == "D", f"Expected receiver 'D', got {row['receiver']}"
    assert float(row["volume"]) == 300.0, f"Expected volume 300.0, got {row['volume']}"
    assert math.isclose(float(row["combined_pagerank"]), 0.5630, abs_tol=0.005), (
        f"Combined PageRank {row['combined_pagerank']} is not within tolerance of 0.5630"
    )

    # Replace Mongo contents with unpredictable entity names and values, then rerun.
    labels = ["entity_" + uuid.uuid4().hex for _ in range(5)]
    A, B, C, D, E = labels
    dynamic_docs = [
        {"sender": A, "receiver": B, "amount": 31},
        {"sender": A, "receiver": B, "amount": 44},
        {"sender": B, "receiver": C, "amount": 113},
        {"sender": C, "receiver": A, "amount": 87},
        {"sender": C, "receiver": D, "amount": 21},
        {"sender": D, "receiver": B, "amount": 191},
        {"sender": A, "receiver": D, "amount": 277},
        {"sender": D, "receiver": E, "amount": 66},
        {"sender": E, "receiver": A, "amount": 79},
        {"sender": B, "receiver": E, "amount": 50}
    ]
    collection.delete_many({})
    collection.insert_many(dynamic_docs)
    reset_profiler(db)
    run_pipeline()
    assert_required_mongo_aggregation(db)

    totals = {}
    for doc in dynamic_docs:
        key = (doc["sender"], doc["receiver"])
        totals[key] = totals.get(key, 0.0) + float(doc["amount"])
    expected_dynamic_edges = {(s, r, v) for (s, r), v in totals.items() if v > 50}

    graph = nx.DiGraph()
    for sender, receiver, volume in expected_dynamic_edges:
        graph.add_edge(sender, receiver, weight=volume)
    expected_pr = nx.pagerank(graph, alpha=0.85, weight="weight")

    actual_edges, actual_nodes = read_db()
    assert set(actual_edges) == expected_dynamic_edges, (
        f"Dynamic edges are incorrect. Expected {expected_dynamic_edges}, got {set(actual_edges)}"
    )
    assert set(actual_nodes) == set(expected_pr), "Dynamic node set is incorrect."
    for node_id, expected in expected_pr.items():
        assert math.isclose(actual_nodes[node_id], expected, rel_tol=1e-7, abs_tol=1e-9), (
            f"Incorrect PageRank for {node_id}: expected {expected}, got {actual_nodes[node_id]}"
        )

    ranked = [
        (expected_pr[s] + expected_pr[r], s, r, v)
        for s, r, v in expected_dynamic_edges
    ]
    ranked.sort(reverse=True)
    assert len(ranked) == 1 or not math.isclose(ranked[0][0], ranked[1][0], abs_tol=1e-12), "Verifier dataset unexpectedly has a tie."
    combined, sender, receiver, volume = ranked[0]
    row = read_csv()
    assert row["sender"] == sender
    assert row["receiver"] == receiver
    assert row["volume"] == f"{volume:.4f}", "CSV volume must be formatted to 4 decimal places."
    assert row["combined_pagerank"] == f"{combined:.4f}", "CSV combined_pagerank must be formatted to 4 decimal places."

    db.command("profile", 0)
    client.close()
TEST_EOF

if python3 -m pytest /tmp/test_etl_pipeline.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
