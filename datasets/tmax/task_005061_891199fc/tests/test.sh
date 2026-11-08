#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "pymongo:pymongo"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import socket
import subprocess
import uuid

import pytest
from pymongo import MongoClient

SCRIPT_PATH = "/home/user/analyze_deadlocks.py"
CSV_PATH = "/home/user/deadlock_report.csv"
EXPECTED_TX42 = [
    ["sequence_order", "tx_id", "waits_for", "operation"],
    ["1", "TX-42", "TX-88", "lock_table_users"],
    ["2", "TX-88", "TX-12", "lock_table_billing"],
    ["3", "TX-12", "TX-42", "lock_table_logs"],
]


def read_csv():
    with open(CSV_PATH, "r", newline="") as f:
        return list(csv.reader(f))


def test_mongodb_directory_exists():
    db_path = "/home/user/mongodb_data"
    assert os.path.isdir(db_path), f"MongoDB data directory {db_path} does not exist."


def test_mongodb_port_open():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(1)
    try:
        result = s.connect_ex(("127.0.0.1", 27017))
        assert result == 0, "MongoDB is not listening on port 27017."
    finally:
        s.close()


def test_analyze_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_csv_report_contents():
    assert os.path.isfile(CSV_PATH), f"CSV report {CSV_PATH} does not exist."
    actual_rows = read_csv()
    assert len(actual_rows) == len(EXPECTED_TX42), (
        f"Expected {len(EXPECTED_TX42)} rows in CSV, got {len(actual_rows)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_rows, EXPECTED_TX42)):
        assert actual == expected, (
            f"Row {i+1} in CSV does not match expected. Got {actual}, expected {expected}."
        )


def test_real_mongodb_and_original_data_loaded():
    client = MongoClient("mongodb://127.0.0.1:27017", serverSelectionTimeoutMS=2000)
    assert client.admin.command("ping")["ok"] == 1
    collection = client.backup_db.transactions
    expected = {
        "TX-42": ("TX-88", "lock_table_users"),
        "TX-88": ("TX-12", "lock_table_billing"),
        "TX-12": ("TX-42", "lock_table_logs"),
    }
    for txid, (waits_for, operation) in expected.items():
        doc = collection.find_one({"_id": txid})
        assert doc is not None, f"{txid} was not loaded into backup_db.transactions"
        assert doc.get("waits_for") == waits_for
        assert doc.get("operation") == operation
    client.close()


def test_script_uses_argparse():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)
    imports_argparse = any(
        (isinstance(node, ast.Import) and any(alias.name == "argparse" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "argparse")
        for node in ast.walk(tree)
    )
    calls = [
        node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    ]
    assert imports_argparse, "The diagnostic script must import argparse."
    assert "ArgumentParser" in calls and "add_argument" in calls, (
        "The diagnostic script must define its --txid CLI using argparse."
    )


def test_script_executes_dynamic_cycle_via_graphlookup():
    client = MongoClient("mongodb://127.0.0.1:27017", serverSelectionTimeoutMS=2000)
    db = client.backup_db
    collection = db.transactions
    token = uuid.uuid4().hex
    ids = [f"VERIFY-{token}-{n}" for n in range(4)]
    docs = [
        {"_id": ids[0], "waits_for": ids[1], "operation": f"verify_op_{token}_a"},
        {"_id": ids[1], "waits_for": ids[2], "operation": f"verify_op_{token}_b"},
        {"_id": ids[2], "waits_for": ids[0], "operation": f"verify_op_{token}_c"},
        {"_id": ids[3], "waits_for": None, "operation": f"verify_decoy_{token}"},
    ]
    expected = [
        ["sequence_order", "tx_id", "waits_for", "operation"],
        ["1", ids[0], ids[1], docs[0]["operation"]],
        ["2", ids[1], ids[2], docs[1]["operation"]],
        ["3", ids[2], ids[0], docs[2]["operation"]],
    ]

    result = None
    rows = None
    profile_entries = []
    try:
        collection.insert_many(docs)
        db.command("profile", 0)
        db["system.profile"].drop()
        db.command("profile", 2)

        result = subprocess.run(
            ["python3", SCRIPT_PATH, "--txid", ids[0]],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        if os.path.isfile(CSV_PATH):
            rows = read_csv()
        profile_entries = list(
            db["system.profile"].find({"command.aggregate": "transactions"}).sort("ts", -1)
        )
    finally:
        try:
            db.command("profile", 0)
        except Exception:
            pass
        collection.delete_many({"_id": {"$in": ids}})
        client.close()
        subprocess.run(
            ["python3", SCRIPT_PATH, "--txid", "TX-42"],
            cwd="/home/user",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
            check=False,
        )

    assert result is not None and result.returncode == 0, (
        "The diagnostic script failed for a parameterized transaction ID.\n"
        f"stdout: {getattr(result, 'stdout', '')}\n"
        f"stderr: {getattr(result, 'stderr', '')}"
    )
    assert rows == expected, f"Dynamic cycle CSV was incorrect. Got {rows}, expected {expected}."
    assert profile_entries, "No aggregation on backup_db.transactions was observed."

    qualifying_pipeline = None
    for entry in profile_entries:
        pipeline = entry.get("command", {}).get("pipeline", [])
        graph_indexes = [i for i, stage in enumerate(pipeline) if "$graphLookup" in stage]
        for graph_index in graph_indexes:
            graph_spec = pipeline[graph_index]["$graphLookup"]
            alias = graph_spec.get("as")
            before = json.dumps(pipeline[:graph_index + 1], default=str)
            later_matches = [
                stage for stage in pipeline[graph_index + 1:] if "$match" in stage
            ]
            if (
                graph_spec.get("from") == "transactions"
                and graph_spec.get("connectFromField") == "waits_for"
                and graph_spec.get("connectToField") == "_id"
                and ids[0] in before
                and alias
                and any(alias in json.dumps(stage, default=str) for stage in later_matches)
            ):
                qualifying_pipeline = pipeline
                break
        if qualifying_pipeline is not None:
            break

    assert qualifying_pipeline is not None, (
        "The executed MongoDB aggregation must use $graphLookup over waits_for -> _id, "
        "start from the requested transaction, and apply a later $match to the graph "
        "hierarchy to detect the cycle."
    )


def test_tx42_report_restored_after_dynamic_check():
    assert os.path.isfile(CSV_PATH)
    assert read_csv() == EXPECTED_TX42
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
