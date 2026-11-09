#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'VALIDATE_EOF' > /tmp/validate_submission.py
import ast
import json
import math
import os
import random
import re
import shutil
import sqlite3
import stat
import subprocess
import tempfile

HOME = "/home/user"
SCRIPT = os.path.join(HOME, "analyze.py")
DB = os.path.join(HOME, "supply_chain.db")
SUPPLIERS = os.path.join(HOME, "suppliers.json")
REPORT = os.path.join(HOME, "optimization_report.json")

assert os.path.isfile(SCRIPT), f"The required Python script {SCRIPT} was not found."
assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"{SCRIPT} must be a regular file."

with open(SCRIPT, "r", encoding="utf-8") as f:
    source = f.read()

tree = ast.parse(source, filename=SCRIPT)
uses_networkx = any(
    (isinstance(node, ast.Import) and any(alias.name == "networkx" for alias in node.names))
    or (isinstance(node, ast.ImportFrom) and node.module == "networkx")
    for node in ast.walk(tree)
)
assert uses_networkx, "analyze.py must import and use the required NetworkX library."
assert re.search(r"\bWITH\s+RECURSIVE\b", source, re.IGNORECASE), \
    "analyze.py must contain the required recursive SQLite CTE."


def expected_cost(rows):
    children = {}
    costs = {}
    qtys = {}
    for cid, _name, pid, qty, cost in rows:
        costs[cid] = cost
        qtys[cid] = qty
        children.setdefault(pid, []).append(cid)

    def calculate(cid):
        return costs[cid] + sum(calculate(child) * qtys[child]
                                for child in children.get(cid, []))
    return calculate(1)


def expected_centrality(rows):
    nodes = {row[0] for row in rows}
    indegrees = {node: 0 for node in nodes}
    for cid, _name, pid, _qty, _cost in rows:
        if pid is not None:
            nodes.add(pid)
            indegrees.setdefault(pid, 0)
            indegrees[cid] = indegrees.get(cid, 0) + 1
    n = len(nodes)
    centrality = {node: (indegrees.get(node, 0) / (n - 1) if n > 1 else 0)
                  for node in nodes}
    return sorted(nodes, key=lambda node: (-centrality[node], node))[:2]


def expected_capacity(documents):
    result = {}
    for supplier in documents:
        for item in supplier.get("inventory", []):
            key = str(item["component_id"])
            result[key] = result.get(key, 0) + item["qty"]
    return result


def install_fixture(rows, documents):
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(DB + suffix)
        except FileNotFoundError:
            pass
    conn = sqlite3.connect(DB)
    try:
        conn.execute("CREATE TABLE components (id INTEGER PRIMARY KEY, name TEXT, parent_id INTEGER, required_qty INTEGER, unit_cost REAL)")
        conn.executemany("INSERT INTO components VALUES (?, ?, ?, ?, ?)", rows)
        conn.commit()
    finally:
        conn.close()
    with open(SUPPLIERS, "w", encoding="utf-8") as f:
        json.dump(documents, f)


def run_and_check(rows, documents):
    try:
        os.remove(REPORT)
    except FileNotFoundError:
        pass
    subprocess.run(["python3", SCRIPT], cwd=HOME, check=True, timeout=30)
    assert os.path.isfile(REPORT), "analyze.py did not create optimization_report.json."
    with open(REPORT, "r", encoding="utf-8") as f:
        report = json.load(f)

    for key in ("total_root_cost", "top_2_central_components", "total_capacity_by_component"):
        assert key in report, f"Missing {key!r} in the generated report."
    want_cost = expected_cost(rows)
    assert math.isclose(report["total_root_cost"], want_cost, rel_tol=1e-5, abs_tol=1e-8), \
        f"Dynamic fixture expected cost {want_cost}, got {report['total_root_cost']}."
    want_centrality = expected_centrality(rows)
    assert report["top_2_central_components"] == want_centrality, \
        f"Dynamic fixture expected central components {want_centrality}, got {report['top_2_central_components']}."
    got_capacity = {str(k): v for k, v in report["total_capacity_by_component"].items()}
    want_capacity = expected_capacity(documents)
    assert got_capacity == want_capacity, \
        f"Dynamic fixture expected capacities {want_capacity}, got {got_capacity}."


with open(DB, "rb") as f:
    original_db = f.read()
with open(SUPPLIERS, "rb") as f:
    original_suppliers = f.read()

rng = random.SystemRandom()
a, b, c, d, e = [rng.randint(2, 9) for _ in range(5)]
fixtures = [
    (
        [
            (1, "Root", None, 1, rng.uniform(1, 9)),
            (9, "BranchA", 1, a, rng.uniform(10, 30)),
            (4, "BranchB", 1, b, rng.uniform(2, 8)),
            (15, "LeafA", 9, c, rng.uniform(0.2, 3)),
            (6, "LeafB", 4, d, rng.uniform(4, 12)),
            (21, "DeepLeaf", 15, e, rng.uniform(0.1, 2)),
        ],
        [
            {"supplier_id": "X", "inventory": [
                {"component_id": 9, "qty": rng.randint(20, 60)},
                {"component_id": 6, "qty": rng.randint(5, 19)}]},
            {"supplier_id": "Y", "inventory": [
                {"component_id": 9, "qty": rng.randint(1, 17)},
                {"component_id": 21, "qty": rng.randint(70, 120)}]},
            {"supplier_id": "EMPTY", "inventory": []},
        ],
    ),
    (
        [
            (1, "Assembly", None, 1, rng.uniform(20, 40)),
            (30, "Part30", 1, rng.randint(2, 6), rng.uniform(3, 9)),
            (12, "Part12", 30, rng.randint(2, 5), rng.uniform(1, 5)),
            (3, "Part3", 12, rng.randint(3, 8), rng.uniform(0.3, 2)),
        ],
        [
            {"supplier_id": "A", "inventory": [
                {"component_id": 3, "qty": rng.randint(2, 30)},
                {"component_id": 12, "qty": rng.randint(20, 50)},
                {"component_id": 3, "qty": rng.randint(31, 60)}]},
            {"supplier_id": "B", "inventory": [
                {"component_id": 99, "qty": rng.randint(4, 14)}]},
        ],
    ),
]

try:
    for rows, documents in fixtures:
        install_fixture(rows, documents)
        run_and_check(rows, documents)
finally:
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(DB + suffix)
        except FileNotFoundError:
            pass
    with open(DB, "wb") as f:
        f.write(original_db)
    with open(SUPPLIERS, "wb") as f:
        f.write(original_suppliers)
VALIDATE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3
import math

def get_expected_cost(db_path):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT id, parent_id, required_qty, unit_cost FROM components")
    rows = c.fetchall()
    conn.close()

    children = {}
    costs = {}
    qtys = {}
    for cid, pid, qty, cost in rows:
        costs[cid] = cost
        qtys[cid] = qty
        if pid not in children:
            children[pid] = []
        children[pid].append(cid)

    def calculate_cost(cid):
        total = costs[cid]
        for child in children.get(cid, []):
            total += calculate_cost(child) * qtys[child]
        return total

    return calculate_cost(1)

def get_expected_centrality(db_path):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT id, parent_id FROM components")
    rows = c.fetchall()
    conn.close()

    in_degrees = {}
    nodes = set()
    for cid, pid in rows:
        nodes.add(cid)
        if pid is not None:
            nodes.add(pid)
            in_degrees[cid] = in_degrees.get(cid, 0) + 1

    for node in nodes:
        if node not in in_degrees:
            in_degrees[node] = 0

    n = len(nodes)
    if n <= 1:
        centrality = {node: 0 for node in nodes}
    else:
        centrality = {node: deg / (n - 1) for node, deg in in_degrees.items()}

    sorted_nodes = sorted(centrality.keys(), key=lambda x: (-centrality[x], x))
    return sorted_nodes[:2]

def get_expected_capacity(json_path):
    with open(json_path, 'r') as f:
        data = json.load(f)

    capacity = {}
    for supplier in data:
        for item in supplier.get("inventory", []):
            cid = str(item["component_id"])
            capacity[cid] = capacity.get(cid, 0) + item["qty"]

    return capacity

def test_optimization_report_exists():
    report_path = "/home/user/optimization_report.json"
    assert os.path.isfile(report_path), f"The report file {report_path} was not found."

def test_optimization_report_contents():
    report_path = "/home/user/optimization_report.json"
    db_path = "/home/user/supply_chain.db"
    suppliers_path = "/home/user/suppliers.json"

    assert os.path.isfile(report_path), "Report file is missing."

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {report_path} does not contain valid JSON."

    assert "total_root_cost" in report, "Missing 'total_root_cost' in the report."
    assert "top_2_central_components" in report, "Missing 'top_2_central_components' in the report."
    assert "total_capacity_by_component" in report, "Missing 'total_capacity_by_component' in the report."

    expected_cost = get_expected_cost(db_path)
    assert math.isclose(report["total_root_cost"], expected_cost, rel_tol=1e-5), \
        f"Expected total_root_cost to be {expected_cost}, but got {report['total_root_cost']}."

    expected_centrality = get_expected_centrality(db_path)
    assert report["top_2_central_components"] == expected_centrality, \
        f"Expected top_2_central_components to be {expected_centrality}, but got {report['top_2_central_components']}."

    expected_capacity = get_expected_capacity(suppliers_path)
    report_capacity = {str(k): v for k, v in report["total_capacity_by_component"].items()}
    assert report_capacity == expected_capacity, \
        f"Expected total_capacity_by_component to be {expected_capacity}, but got {report_capacity}."
TEST_EOF

if python3 /tmp/validate_submission.py 2>&1 \
   && cd /home/user \
   && timeout 30s python3 /home/user/analyze.py 2>&1 \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
