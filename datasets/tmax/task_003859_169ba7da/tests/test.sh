#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import io
import json
import os
import re
import secrets
import sqlite3
import subprocess
from collections import Counter

import pytest

BASE = "/home/user/compliance_audit"
CSV_PATH = os.path.join(BASE, "tx_data.csv")
DB_PATH = os.path.join(BASE, "audit.db")
REPORT_PATH = os.path.join(BASE, "report.json")
INGEST_PATH = os.path.join(BASE, "ingest.py")
DETECT_PATH = os.path.join(BASE, "detect_cycles.py")


def run_script(path, *args):
    return subprocess.run(
        ["python3", path, *map(str, args)],
        cwd=BASE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=90,
        check=True,
    )


def remove_outputs():
    for path in (DB_PATH, REPORT_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def csv_rows(data):
    text = data.decode("utf-8") if isinstance(data, bytes) else data
    reader = csv.DictReader(io.StringIO(text))
    assert reader.fieldnames == ["tx_id", "sender_id", "receiver_id", "amount", "timestamp"]
    return Counter(
        (int(r["tx_id"]), r["sender_id"], r["receiver_id"], float(r["amount"]), r["timestamp"])
        for r in reader
    )


def assert_database_matches(data):
    assert os.path.isfile(DB_PATH), f"Database file not found at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    try:
        table = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='transactions'"
        ).fetchone()
        assert table is not None, "Table 'transactions' does not exist in the database."
        actual = Counter(conn.execute(
            "SELECT tx_id, sender_id, receiver_id, amount, timestamp FROM transactions"
        ).fetchall())
        assert actual == csv_rows(data), "The transactions table is not an exact ingestion of tx_data.csv"
        indexes = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='transactions'"
        ).fetchall()
        assert len(indexes) > 0, "No indexes found on the 'transactions' table. Indexing strategy is missing."
    finally:
        conn.close()


def resolve_string(node, assignments):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name) and node.id in assignments:
        return resolve_string(assignments[node.id], assignments)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = resolve_string(node.left, assignments)
        right = resolve_string(node.right, assignments)
        if left is not None and right is not None:
            return left + right
    return None


def assert_parameterized_join_source():
    with open(DETECT_PATH, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=DETECT_PATH)

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assignments[target.id] = node.value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            assignments[node.target.id] = node.value

    qualifying = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr not in ("execute", "executemany") or len(node.args) < 2:
            continue
        sql = resolve_string(node.args[0], assignments)
        if sql is None:
            continue
        lowered = " ".join(sql.lower().split())
        has_three_way_join = lowered.count(" join ") >= 2 or lowered.count("transactions") >= 3
        has_placeholder = re.search(r"\?|[:@$][A-Za-z_][A-Za-z0-9_]*", sql) is not None
        if "transactions" in lowered and has_three_way_join and has_placeholder:
            qualifying.append(node)

    assert qualifying, (
        "detect_cycles.py must execute a parameterized three-way SQL join; the threshold "
        "must be supplied separately from the SQL string"
    )


def expected_cycles(rows, threshold):
    edges = [(s, r, float(a)) for _, s, r, a, _ in rows if float(a) > threshold]
    outgoing = {}
    for sender, receiver, amount in edges:
        outgoing.setdefault(sender, []).append((receiver, amount))

    found = {}
    for a, b, ab in edges:
        for c, bc in outgoing.get(b, []):
            for end, ca in outgoing.get(c, []):
                if end == a and len({a, b, c}) == 3:
                    nodes = tuple(sorted((a, b, c)))
                    bottleneck = min(ab, bc, ca)
                    if nodes in found:
                        assert found[nodes] == bottleneck
                    found[nodes] = bottleneck

    result = [
        {"node1": n[0], "node2": n[1], "node3": n[2], "bottleneck_amount": amount}
        for n, amount in found.items()
    ]
    return sorted(result, key=lambda item: (-item["bottleneck_amount"], item["node1"]))


def assert_report(rows, threshold):
    assert os.path.isfile(REPORT_PATH), f"Report file not found at {REPORT_PATH}"
    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        report = json.load(f)
    assert set(report) == {"audit_threshold", "cycles_detected"}
    assert report["audit_threshold"] == float(threshold)
    assert isinstance(report["cycles_detected"], list)
    assert report["cycles_detected"] == expected_cycles(rows, threshold)
    for cycle in report["cycles_detected"]:
        assert set(cycle) == {"node1", "node2", "node3", "bottleneck_amount"}
        assert cycle["node1"] < cycle["node2"] < cycle["node3"]


def test_scripts_execute_ingest_source_data_and_detect_runtime_cycles():
    assert os.path.isfile(INGEST_PATH), f"Ingestion script not found at {INGEST_PATH}"
    assert os.path.isfile(DETECT_PATH), f"Cycle detector not found at {DETECT_PATH}"
    assert_parameterized_join_source()

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    try:
        # Execute the submitted pipeline on the supplied source data.
        remove_outputs()
        run_script(INGEST_PATH)
        assert_database_matches(original_csv)
        run_script(DETECT_PATH, 50000.0)

        # Exercise the same pipeline on unpredictable data and thresholds so a
        # hardcoded report or fake database cannot pass.
        tag = secrets.token_hex(6).upper()
        threshold = float(secrets.randbelow(20000) + 20000)
        names = [f"N{tag}{i}" for i in range(10)]
        rows = [
            (1, names[0], names[1], threshold + 7000.0, "2024-01-01T00:00:00Z"),
            (2, names[1], names[2], threshold + 9000.0, "2024-01-01T00:00:01Z"),
            (3, names[2], names[0], threshold + 8000.0, "2024-01-01T00:00:02Z"),
            (4, names[3], names[4], threshold + 3000.0, "2024-01-01T00:00:03Z"),
            (5, names[4], names[5], threshold + 5000.0, "2024-01-01T00:00:04Z"),
            (6, names[5], names[3], threshold + 4000.0, "2024-01-01T00:00:05Z"),
            (7, names[6], names[7], threshold + 6000.0, "2024-01-01T00:00:06Z"),
            (8, names[7], names[8], threshold - 1.0, "2024-01-01T00:00:07Z"),
            (9, names[8], names[6], threshold + 6000.0, "2024-01-01T00:00:08Z"),
            (10, names[9], names[0], threshold + 10000.0, "2024-01-01T00:00:09Z"),
        ]
        out = io.StringIO()
        writer = csv.writer(out, lineterminator="\n")
        writer.writerow(["tx_id", "sender_id", "receiver_id", "amount", "timestamp"])
        writer.writerows(rows)
        synthetic_csv = out.getvalue().encode("utf-8")
        with open(CSV_PATH, "wb") as f:
            f.write(synthetic_csv)

        remove_outputs()
        run_script(INGEST_PATH)
        assert_database_matches(synthetic_csv)
        run_script(DETECT_PATH, threshold)
        assert_report(rows, threshold)
        run_script(DETECT_PATH, threshold + 4500.0)
        assert_report(rows, threshold + 4500.0)
    finally:
        # Restore and regenerate the final state required by the instruction.
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        remove_outputs()
        run_script(INGEST_PATH)
        run_script(DETECT_PATH, 50000.0)


def test_db_exists():
    assert os.path.isfile(DB_PATH), f"Database file not found at {DB_PATH}"


def test_transactions_table_and_indexes():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='transactions';")
    table = cursor.fetchone()
    assert table is not None, "Table 'transactions' does not exist in the database."
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='transactions';")
    indexes = cursor.fetchall()
    assert len(indexes) > 0, "No indexes found on the 'transactions' table. Indexing strategy is missing."
    conn.close()


def test_database_contains_supplied_transactions():
    with open(CSV_PATH, "rb") as f:
        assert_database_matches(f.read())


def test_report_json_exists():
    assert os.path.isfile(REPORT_PATH), f"Report file not found at {REPORT_PATH}"


def test_report_json_content():
    with open(REPORT_PATH, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("report.json is not a valid JSON file.")

    assert "audit_threshold" in report, "Missing 'audit_threshold' in report.json"
    assert report["audit_threshold"] == 50000.0, f"Expected audit_threshold 50000.0, got {report['audit_threshold']}"
    assert "cycles_detected" in report, "Missing 'cycles_detected' in report.json"
    cycles = report["cycles_detected"]
    assert isinstance(cycles, list), "'cycles_detected' must be a list."

    expected_cycles = [
        {"node1": "U4444", "node2": "U5555", "node3": "U6666", "bottleneck_amount": 80000.0},
        {"node1": "U1111", "node2": "U2222", "node3": "U3333", "bottleneck_amount": 55000.0}
    ]
    assert len(cycles) == len(expected_cycles), f"Expected {len(expected_cycles)} cycles, found {len(cycles)}."
    for i, (actual, expected) in enumerate(zip(cycles, expected_cycles)):
        assert "node1" in actual and "node2" in actual and "node3" in actual and "bottleneck_amount" in actual, \
            f"Cycle at index {i} is missing required keys."
        assert actual["node1"] == expected["node1"], f"Expected node1 '{expected['node1']}' at index {i}, got '{actual['node1']}'"
        assert actual["node2"] == expected["node2"], f"Expected node2 '{expected['node2']}' at index {i}, got '{actual['node2']}'"
        assert actual["node3"] == expected["node3"], f"Expected node3 '{expected['node3']}' at index {i}, got '{actual['node3']}'"
        assert actual["bottleneck_amount"] == expected["bottleneck_amount"], \
            f"Expected bottleneck_amount {expected['bottleneck_amount']} at index {i}, got {actual['bottleneck_amount']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
