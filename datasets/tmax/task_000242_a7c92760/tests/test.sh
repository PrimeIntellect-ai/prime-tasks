#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import subprocess
import uuid

import networkx as nx
from pymongo import MongoClient

SCRIPT_PATH = "/home/user/audit.py"
OUTPUT_PATH = "/home/user/flagged_accounts.json"


def run_audit():
    completed = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert completed.returncode == 0, (
        f"audit.py failed with exit code {completed.returncode}\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def load_output():
    assert os.path.exists(OUTPUT_PATH), f"Output file is missing at {OUTPUT_PATH}"
    assert os.path.isfile(OUTPUT_PATH), f"Output path {OUTPUT_PATH} is not a file"
    try:
        with open(OUTPUT_PATH, "r") as handle:
            results = json.load(handle)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"Output file {OUTPUT_PATH} is not valid JSON: {exc}")

    assert isinstance(results, list), "Output must be a JSON array"
    assert len(results) == 3, f"Expected exactly 3 accounts in the output, got {len(results)}"
    for item in results:
        assert isinstance(item, dict), "Each item in the output array must be a JSON object"
        assert "account" in item, "Each object must have an 'account' key"
        assert "pagerank" in item, "Each object must have a 'pagerank' key"
        assert isinstance(item["account"], str), "'account' must be a string"
        assert isinstance(item["pagerank"], (int, float)), "'pagerank' must be a number"
        assert not isinstance(item["pagerank"], bool), "'pagerank' must be a numeric score"
        assert math.isfinite(item["pagerank"]), "'pagerank' must be finite"

    pageranks = [item["pagerank"] for item in results]
    assert pageranks == sorted(pageranks, reverse=True), (
        "Output is not sorted in descending order by PageRank"
    )
    assert len({item["account"] for item in results}) == 3, (
        "The three output accounts must be distinct"
    )
    return results


def expected_from_database(collection):
    pipeline = [
        {
            "$group": {
                "_id": {"sender": "$sender", "receiver": "$receiver"},
                "total": {"$sum": "$amount"},
            }
        },
        {"$match": {"total": {"$gt": 10000}}},
    ]
    pairs = list(collection.aggregate(pipeline))
    graph = nx.DiGraph()
    for pair in pairs:
        graph.add_edge(pair["_id"]["sender"], pair["_id"]["receiver"])

    assert graph.number_of_nodes() > 0, "The filtered transaction graph is unexpectedly empty"
    cycle_nodes = set()
    for cycle in nx.simple_cycles(graph):
        cycle_nodes.update(cycle)
    assert len(cycle_nodes) >= 3, "Expected at least three accounts participating in cycles"

    ranks = nx.pagerank(graph, alpha=0.85)
    ranked_values = sorted((ranks[node] for node in cycle_nodes), reverse=True)
    cutoff = ranked_values[2]
    required = {node for node in cycle_nodes if ranks[node] > cutoff + 1e-12}
    eligible = {node for node in cycle_nodes if ranks[node] >= cutoff - 1e-12}
    return cycle_nodes, ranks, required, eligible


def assert_matches_database(results, collection):
    cycle_nodes, ranks, required, eligible = expected_from_database(collection)
    actual = {item["account"] for item in results}
    assert required.issubset(actual), "Output omits an account ranked above the top-3 cutoff"
    assert actual.issubset(eligible), "Output contains an account outside the top 3 by PageRank"

    for item in results:
        account = item["account"]
        assert account in cycle_nodes, f"Account {account} is not part of a directed cycle"
        assert math.isclose(item["pagerank"], ranks[account], rel_tol=1e-6, abs_tol=5.1e-5), (
            f"Incorrect PageRank for {account}: got {item['pagerank']}, expected {ranks[account]}"
        )


def test_complete_audit_behavior():
    assert os.path.exists(SCRIPT_PATH), f"Audit script is missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Audit script {SCRIPT_PATH} is not a file"

    with open(SCRIPT_PATH, "r") as handle:
        source = handle.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        raise AssertionError(f"Audit script is not valid Python: {exc}")
    assert any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "aggregate"
        for node in ast.walk(tree)
    ), "audit.py must execute a MongoDB aggregation pipeline"

    client = MongoClient("mongodb://localhost:27017/", serverSelectionTimeoutMS=5000)
    client.admin.command("ping")
    collection = client["audit"]["financial_tx"]
    assert collection.count_documents({}) > 0, "The financial_tx collection is empty"

    # Execute and check the requested artifact against the original transaction data.
    run_audit()
    original_results = load_output()
    assert original_results[0]["account"] == "AccC", (
        "The highest PageRank account in a cycle should be AccC"
    )
    valid_cycle_accounts = {"AccA", "AccB", "AccC", "AccD", "AccE"}
    for item in original_results:
        assert item["account"] in valid_cycle_accounts, (
            f"Account {item['account']} is not part of a valid cycle"
        )
    assert_matches_database(original_results, collection)

    # Exercise the script on an unknown graph extension. Split transfers test pair
    # aggregation, and the exactly-10000 edge tests the strict threshold.
    token = uuid.uuid4().hex
    hub = f"ProbeHub_{token}"
    spoke = f"ProbeSpoke_{token}"
    boundary = f"ProbeBoundary_{token}"
    feeders = [f"ProbeFeeder{i}_{token}" for i in range(5)]
    docs = [
        {"sender": feeder, "receiver": hub, "amount": 12001,
         "currency": "USD", "timestamp": "2099-01-01T00:00:00Z"}
        for feeder in feeders
    ]
    docs.extend([
        {"sender": hub, "receiver": spoke, "amount": 6000,
         "currency": "USD", "timestamp": "2099-01-01T00:00:01Z"},
        {"sender": hub, "receiver": spoke, "amount": 5001,
         "currency": "USD", "timestamp": "2099-01-01T00:00:02Z"},
        {"sender": spoke, "receiver": hub, "amount": 13000,
         "currency": "USD", "timestamp": "2099-01-01T00:00:03Z"},
        {"sender": hub, "receiver": boundary, "amount": 10000,
         "currency": "USD", "timestamp": "2099-01-01T00:00:04Z"},
        {"sender": boundary, "receiver": hub, "amount": 15000,
         "currency": "USD", "timestamp": "2099-01-01T00:00:05Z"},
    ])

    inserted_ids = []
    try:
        inserted_ids = collection.insert_many(docs).inserted_ids
        run_audit()
        probe_results = load_output()
        assert_matches_database(probe_results, collection)
        assert any(item["account"] in {hub, spoke} for item in probe_results), (
            "audit.py did not respond to the verifier's transaction data"
        )
    finally:
        if inserted_ids:
            collection.delete_many({"_id": {"$in": inserted_ids}})
        # Leave the requested output corresponding to the original database.
        run_audit()
        restored_results = load_output()
        assert_matches_database(restored_results, collection)
        client.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
