#!/bin/bash
set +e
mkdir -p /logs/verifier
status=0

rm -f /home/user/audit_graph /home/user/audit.db /home/user/violations.log
if gcc -o /home/user/audit_graph /home/user/audit_graph.c -lsqlite3 && \
   test -x /home/user/audit_graph && \
   /home/user/audit_graph; then

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import sqlite3
from collections import Counter


def csv_rows(path, columns):
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == list(columns)
        return [tuple(row[c] for c in columns) for row in reader]


def indexed_columns(conn, table):
    names = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name=?",
        (table,),
    ).fetchall()
    result = set()
    for (name,) in names:
        quoted = name.replace('"', '""')
        result.update(row[2] for row in conn.execute(f'PRAGMA index_info("{quoted}")'))
    return names, result


def test_c_source_file_exists():
    path = "/home/user/audit_graph.c"
    assert os.path.isfile(path), f"Expected C source file {path} is missing."
    with open(path, encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert re.search(r'#\s*include\s*[<\"]sqlite3\.h[>\"]', source), \
        "The C source does not include sqlite3.h."
    assert re.search(r'\bsqlite3_open(?:_v2)?\s*\(', source), \
        "The C source does not open the database through the SQLite3 C API."
    assert os.path.isfile("/home/user/audit_graph") and os.access("/home/user/audit_graph", os.X_OK)


def test_database_exists():
    path = "/home/user/audit.db"
    assert os.path.isfile(path), f"Expected SQLite database {path} is missing."


def test_violations_log_content():
    path = "/home/user/violations.log"
    assert os.path.isfile(path), f"Expected log file {path} is missing."

    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected = ["U1,S1", "U2,S2"]
    assert lines == expected, f"Content of {path} does not match the expected SoD violations. Got: {lines}, Expected: {expected}"


def test_database_schema_and_csv_data():
    conn = sqlite3.connect("/home/user/audit.db")
    try:
        nodes_schema = [(r[1], r[2].upper()) for r in conn.execute("PRAGMA table_info(nodes)")]
        edges_schema = [(r[1], r[2].upper()) for r in conn.execute("PRAGMA table_info(edges)")]
        assert nodes_schema == [("id", "TEXT"), ("type", "TEXT")]
        assert edges_schema == [("source", "TEXT"), ("target", "TEXT"), ("relation", "TEXT")]

        expected_nodes = csv_rows("/home/user/nodes.csv", ("id", "type"))
        expected_edges = csv_rows("/home/user/edges.csv", ("source", "target", "relation"))
        assert Counter(conn.execute("SELECT id, type FROM nodes")) == Counter(expected_nodes)
        assert Counter(conn.execute("SELECT source, target, relation FROM edges")) == Counter(expected_edges)
    finally:
        conn.close()


def test_database_indexes():
    db_path = "/home/user/audit.db"
    assert os.path.isfile(db_path), f"Database {db_path} is missing."

    conn = sqlite3.connect(db_path)
    try:
        edges_indexes, edges_columns = indexed_columns(conn, "edges")
        assert len(edges_indexes) > 0, "No indexes were created on the 'edges' table."

        nodes_indexes, nodes_columns = indexed_columns(conn, "nodes")
        assert len(nodes_indexes) > 0, "No indexes were created on the 'nodes' table."

        assert "id" in nodes_columns, "The nodes indexes do not index the graph node id."
        assert {"source", "relation"}.issubset(edges_columns), \
            "The edges indexes do not support source/relation graph traversal."
    finally:
        conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short; then
cat << 'DYNAMIC_EOF' > /tmp/test_dynamic.py
import csv
import os
import random
import sqlite3
import subprocess
import uuid
from collections import Counter

nodes_path = "/home/user/nodes.csv"
edges_path = "/home/user/edges.csv"
exe = "/home/user/audit_graph"
db_path = "/home/user/audit.db"
log_path = "/home/user/violations.log"

with open(nodes_path, "rb") as f:
    original_nodes = f.read()
with open(edges_path, "rb") as f:
    original_edges = f.read()

tag = uuid.uuid4().hex[:10]
def ident(prefix):
    return prefix + "_" + tag

nodes = [
    (ident("alice"), "User"), (ident("bob"), "User"),
    (ident("carol"), "User"), (ident("dave"), "User"),
    (ident("r1"), "Role"), (ident("r2"), "Role"),
    (ident("r3"), "Role"), (ident("r4"), "Role"),
    (ident("r5"), "Role"),
    (ident("sysA"), "System"), (ident("sysB"), "System"),
    (ident("sysC"), "System"),
]
edges = [
    (ident("alice"), ident("r1"), "has_role"),
    (ident("alice"), ident("r2"), "has_role"),
    (ident("r1"), ident("sysA"), "can_request"),
    (ident("r2"), ident("sysA"), "can_approve"),
    (ident("r1"), ident("sysB"), "can_request"),
    (ident("bob"), ident("r3"), "has_role"),
    (ident("r3"), ident("sysB"), "can_request"),
    (ident("r3"), ident("sysB"), "can_approve"),
    (ident("carol"), ident("r4"), "has_role"),
    (ident("r4"), ident("sysC"), "can_request"),
    (ident("dave"), ident("r5"), "has_role"),
    (ident("r5"), ident("sysA"), "can_approve"),
]
random.SystemRandom().shuffle(nodes)
random.SystemRandom().shuffle(edges)

def oracle(nodes, edges):
    types = dict(nodes)
    roles = {}
    requests = set()
    approvals = set()
    for source, target, relation in edges:
        if relation == "has_role":
            roles.setdefault(source, set()).add(target)
        elif relation == "can_request":
            requests.add((source, target))
        elif relation == "can_approve":
            approvals.add((source, target))
    found = set()
    for user, user_roles in roles.items():
        if types.get(user) != "User":
            continue
        for request_role in user_roles:
            for system in (s for r, s in requests if r == request_role):
                if types.get(system) != "System":
                    continue
                if any((approve_role, system) in approvals for approve_role in user_roles):
                    found.add((user, system))
    return sorted(f"{user},{system}" for user, system in found)

try:
    with open(nodes_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(("id", "type"))
        writer.writerows(nodes)
    with open(edges_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(("source", "target", "relation"))
        writer.writerows(edges)

    for path in (db_path, log_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    subprocess.run([exe], check=True, timeout=15)

    with open(log_path) as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == oracle(nodes, edges), (actual, oracle(nodes, edges))

    conn = sqlite3.connect(db_path)
    try:
        assert Counter(conn.execute("SELECT id, type FROM nodes")) == Counter(nodes)
        assert Counter(conn.execute("SELECT source, target, relation FROM edges")) == Counter(edges)
        assert [(r[1], r[2].upper()) for r in conn.execute("PRAGMA table_info(nodes)")] == [
            ("id", "TEXT"), ("type", "TEXT")]
        assert [(r[1], r[2].upper()) for r in conn.execute("PRAGMA table_info(edges)")] == [
            ("source", "TEXT"), ("target", "TEXT"), ("relation", "TEXT")]
    finally:
        conn.close()
finally:
    with open(nodes_path, "wb") as f:
        f.write(original_nodes)
    with open(edges_path, "wb") as f:
        f.write(original_edges)
    for path in (db_path, log_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    subprocess.run([exe], check=True, timeout=15)
DYNAMIC_EOF

  if python3 /tmp/test_dynamic.py; then
    status=1
  fi
fi
fi

echo "$status" > /logs/verifier/reward.txt
exit 0
