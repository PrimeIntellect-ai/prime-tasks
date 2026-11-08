#!/bin/bash
set +e
set -o pipefail
mkdir -p /logs/verifier

DB=/home/user/data/experiment.db
BACKUP=/tmp/experiment.db.verifier-backup
cp "$DB" "$BACKUP" 2>/dev/null

verify() {
    test -f /home/user/process.cpp || return 1

    rm -f /home/user/process
    g++ -std=c++17 /home/user/process.cpp -lsqlite3 -o /home/user/process || return 1
    test -f /home/user/process || return 1
    test -x /home/user/process || return 1

    # Confirm that the submitted executable actually references SQLite's C API.
    nm -D /home/user/process 2>/dev/null | grep -Eq ' U sqlite3_(open|open_v2)(@|$)' || return 1
    nm -D /home/user/process 2>/dev/null | grep -Eq ' U sqlite3_(exec|get_table|prepare|prepare_v2|prepare_v3)(@|$)' || return 1

    # Execute the artifact against the original database before checking the
    # original verifier's assertions.
    rm -f /home/user/nodes.csv /home/user/edges.csv
    before_hash=$(sha256sum "$DB" | awk '{print $1}') || return 1
    (cd /home/user && timeout 20s ./process) || return 1
    after_hash=$(sha256sum "$DB" | awk '{print $1}') || return 1
    test "$before_hash" = "$after_hash" || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

def test_process_cpp_exists():
    assert os.path.isfile("/home/user/process.cpp"), "The file /home/user/process.cpp is missing."

def test_nodes_csv():
    nodes_csv_path = "/home/user/nodes.csv"
    assert os.path.isfile(nodes_csv_path), f"The file {nodes_csv_path} is missing."

    with open(nodes_csv_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "1,Alpha,1",
        "2,Beta,2",
        "3,Gamma,2",
        "5,Epsilon,1"
    ]

    if lines and (lines[0].lower().startswith("id") or lines[0].lower().startswith("c_id")):
        lines = lines[1:]

    assert lines == expected_lines, f"The content of {nodes_csv_path} does not match the expected output."

def test_edges_csv():
    edges_csv_path = "/home/user/edges.csv"
    assert os.path.isfile(edges_csv_path), f"The file {edges_csv_path} is missing."

    with open(edges_csv_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "1,2,6.5",
        "2,3,5.5",
        "3,5,5.1"
    ]

    if lines and (lines[0].lower().startswith("src") or lines[0].lower().startswith("c_a")):
        lines = lines[1:]

    parsed_lines = []
    for line in lines:
        parts = line.split(',')
        if len(parts) == 3:
            parsed_lines.append((int(parts[0]), int(parts[1]), float(parts[2])))
        else:
            parsed_lines.append(line)

    expected_parsed = [
        (1, 2, 6.5),
        (2, 3, 5.5),
        (3, 5, 5.1)
    ]

    assert parsed_lines == expected_parsed, f"The content of {edges_csv_path} does not match the expected output."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    # Change labels, categories, strengths, and add randomized entities and
    # interactions so fixed CSV output cannot pass the second execution.
    python3 - << 'PY' || return 1
import secrets
import sqlite3

path = "/home/user/data/experiment.db"
con = sqlite3.connect(path)
cur = con.cursor()
used = {row[0] for row in cur.execute("SELECT c_id FROM t_001")}
ids = []
while len(ids) < 4:
    value = 100000 + secrets.randbelow(800000)
    if value not in used:
        used.add(value)
        ids.append(value)
x, y, z, b = ids
suffix = secrets.token_hex(5)
cur.execute("UPDATE t_001 SET c_label=? WHERE c_id=1", ("Alpha_" + suffix,))
cur.execute("UPDATE t_001 SET c_cat='B' WHERE c_id=2")
cur.execute("UPDATE t_002 SET c_val=? WHERE c_a=3 AND c_b=5", (7.0 + secrets.randbelow(200) / 10.0,))
cur.executemany(
    "INSERT INTO t_001(c_id,c_label,c_cat) VALUES (?,?,?)",
    [
        (x, "X_" + suffix, "A"),
        (y, "Y_" + suffix, "A"),
        (z, "Z_" + suffix, "A"),
        (b, "B_" + suffix, "B"),
    ],
)
strong1 = 6.0 + secrets.randbelow(300) / 10.0
strong2 = 6.0 + secrets.randbelow(300) / 10.0
cur.executemany(
    "INSERT INTO t_002(c_a,c_b,c_val) VALUES (?,?,?)",
    [
        (x, y, strong1),
        (1, x, strong2),
        (y, z, 5.0),
        (x, b, strong1 + 1.0),
    ],
)
con.commit()
con.close()
PY

    rm -f /home/user/nodes.csv /home/user/edges.csv
    before_hash=$(sha256sum "$DB" | awk '{print $1}') || return 1
    (cd /home/user && timeout 20s ./process) || return 1
    after_hash=$(sha256sum "$DB" | awk '{print $1}') || return 1
    test "$before_hash" = "$after_hash" || return 1

    # Derive the expected result independently from the mutated database.
    python3 - << 'PY' || return 1
import math
import os
import sqlite3

DB = "/home/user/data/experiment.db"
NODES = "/home/user/nodes.csv"
EDGES = "/home/user/edges.csv"
assert os.path.isfile(NODES), "The file /home/user/nodes.csv is missing after execution."
assert os.path.isfile(EDGES), "The file /home/user/edges.csv is missing after execution."

con = sqlite3.connect(DB)
entities = list(con.execute(
    "SELECT c_id, c_label FROM t_001 WHERE c_cat = 'A' ORDER BY c_id"
))
edges = list(con.execute(
    "SELECT e.c_a, e.c_b, e.c_val "
    "FROM t_002 e "
    "JOIN t_001 s ON s.c_id=e.c_a "
    "JOIN t_001 d ON d.c_id=e.c_b "
    "WHERE s.c_cat='A' AND d.c_cat='A' AND e.c_val>5.0 "
    "ORDER BY e.c_a, e.c_b"
))
con.close()

degree = {entity_id: 0 for entity_id, _ in entities}
for src, dst, _ in edges:
    degree[src] += 1
    degree[dst] += 1
expected_nodes = [(entity_id, label, degree[entity_id]) for entity_id, label in entities]

def nonempty_lines(path):
    with open(path, encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]

node_lines = nonempty_lines(NODES)
if node_lines and (node_lines[0].lower().startswith("id") or node_lines[0].lower().startswith("c_id")):
    node_lines = node_lines[1:]
actual_nodes = []
for line in node_lines:
    parts = line.split(',')
    assert len(parts) == 3, f"Malformed node row: {line!r}"
    actual_nodes.append((int(parts[0]), parts[1], int(parts[2])))
assert actual_nodes == expected_nodes, "nodes.csv was not derived correctly from the mutated database"

edge_lines = nonempty_lines(EDGES)
if edge_lines and (edge_lines[0].lower().startswith("src") or edge_lines[0].lower().startswith("c_a")):
    edge_lines = edge_lines[1:]
actual_edges = []
for line in edge_lines:
    parts = line.split(',')
    assert len(parts) == 3, f"Malformed edge row: {line!r}"
    actual_edges.append((int(parts[0]), int(parts[1]), float(parts[2])))
assert len(actual_edges) == len(edges), "Wrong number of edge rows"
for actual, expected in zip(actual_edges, edges):
    assert actual[:2] == expected[:2], "edges.csv is not sorted or has incorrect endpoints"
    assert math.isclose(actual[2], expected[2], rel_tol=1e-9, abs_tol=1e-9), "Incorrect edge value"
PY
}

verify
result=$?

if test -f "$BACKUP"; then
    cp "$BACKUP" "$DB"
    rm -f /home/user/data/experiment.db-wal /home/user/data/experiment.db-shm
fi

if test "$result" -eq 0; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
