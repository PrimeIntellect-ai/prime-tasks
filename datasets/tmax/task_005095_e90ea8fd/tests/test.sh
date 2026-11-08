#!/bin/bash
set -e
mkdir -p /logs/verifier

REAL_SQLITE=/usr/bin/sqlite3.verifier-real
if [ ! -e "$REAL_SQLITE" ]; then
    mv /usr/bin/sqlite3 "$REAL_SQLITE"
fi

cat > /usr/bin/sqlite3 <<'WRAPPER_EOF'
#!/bin/bash
set -e
logdir="${SQLITE_AUDIT_DIR:-/tmp/sqlite-audit}"
mkdir -p "$logdir"
input=$(mktemp)
cat > "$input"
log=$(mktemp "$logdir/call.XXXXXX")
{
    echo '---ARGV---'
    printf '%s\n' "$@"
    echo '---STDIN---'
    cat "$input"
} > "$log"
exec /usr/bin/sqlite3.verifier-real "$@" < "$input"
WRAPPER_EOF
chmod 755 /usr/bin/sqlite3

cleanup() {
    rm -f /usr/bin/sqlite3
    if [ -e "$REAL_SQLITE" ]; then
        mv "$REAL_SQLITE" /usr/bin/sqlite3
    fi
}
trap cleanup EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import re
import shutil
import sqlite3
import stat
import subprocess
from collections import Counter
from decimal import Decimal

SCRIPT_PATH = "/home/user/process_graph.sh"
DB_PATH = "/home/user/graph.db"
TOP_PATHS_CSV = "/home/user/top_paths.csv"
QUERY_PLAN_TXT = "/home/user/query_plan.txt"
NODES_CSV = "/home/user/nodes.csv"
EDGES_CSV = "/home/user/edges.csv"

ORIGINAL_NODES = """id,name,type
1,Alice,Person
2,Bob,Person
3,Charlie,Person
4,Diana,Person
5,Eve,Person
6,Frank,Person
"""
ORIGINAL_EDGES = """source,target,amount,timestamp
1,2,100,1600000000
2,3,200,1600000100
1,4,150,1600000050
4,5,500,1600000200
5,6,600,1600000300
2,6,150,1600000150
3,1,50,1600000400
4,1,100,1600000250
"""

DYNAMIC_NODES = """id,name,type
10,Alpha,Person
20,Beta,Business
30,Gamma,Person
40,Delta,Business
50,Epsilon,Person
60,Zed,Person
70,Eta,Person
"""
DYNAMIC_EDGES = """source,target,amount,timestamp
10,20,100,100
20,50,300,200
10,40,150,110
40,30,250,210
50,60,500,300
30,70,200,400
60,70,500,500
70,10,50,600
40,70,140,205
"""


def write_fixture(nodes_text, edges_text):
    with open(NODES_CSV, "w", newline="") as f:
        f.write(nodes_text)
    with open(EDGES_CSV, "w", newline="") as f:
        f.write(edges_text)


def read_fixture():
    with open(NODES_CSV, newline="") as f:
        nodes = list(csv.DictReader(f))
    with open(EDGES_CSV, newline="") as f:
        edges = list(csv.DictReader(f))
    return nodes, edges


def expected_paths(nodes, edges):
    names = {int(n["id"]): n["name"] for n in nodes}
    parsed = [
        (int(e["source"]), int(e["target"]), Decimal(e["amount"]), int(e["timestamp"]))
        for e in edges
    ]
    candidates = {}
    for e1 in parsed:
        for e2 in parsed:
            if e1[1] == e2[0] and e1[3] < e2[3] and e1[2] < e2[2]:
                item = (e1[2] + e2[2], e2[1], e1[1])
                candidates.setdefault(e1[0], []).append(item)
    answer = []
    for start, choices in candidates.items():
        total, end, middle = sorted(choices, key=lambda x: (-x[0], x[1]))[0]
        amount = format(total, "f").rstrip("0").rstrip(".") if "." in format(total, "f") else format(total, "f")
        answer.append((names[start], names[middle], names[end], amount))
    return Counter(answer)


def canonical_db_amount(value):
    return Decimal(str(value))


def normalize_sql(text):
    return re.sub(r"\s+", " ", text).strip().rstrip(";").strip().lower()


def read_audit(logdir):
    return "\n".join(open(p, errors="replace").read() for p in sorted(glob.glob(logdir + "/call.*")))


def find_analytical_query(audit, conn, expected):
    pattern = re.compile(r"EXPLAIN\s+QUERY\s+PLAN\s+((?:WITH|SELECT)\b.*?;)", re.I | re.S)
    matches = pattern.findall(audit)
    assert matches, "The script did not run EXPLAIN QUERY PLAN on a SELECT/WITH query."

    for query in matches:
        if not re.search(r"\b(?:ROW_NUMBER|RANK|DENSE_RANK|FIRST_VALUE|NTH_VALUE)\s*\([^)]*\)\s*OVER\s*\(", query, re.I | re.S):
            continue
        try:
            rows = conn.execute(query.rstrip().rstrip(";")).fetchall()
        except sqlite3.Error:
            continue

        converted = []
        valid = True
        for row in rows:
            if len(row) == 4:
                vals = list(row)
            elif len(row) == 1:
                vals = next(csv.reader([str(row[0])]))
            else:
                valid = False
                break
            if len(vals) != 4:
                valid = False
                break
            try:
                total = Decimal(str(vals[3]))
                total_text = format(total, "f").rstrip("0").rstrip(".") if "." in format(total, "f") else format(total, "f")
            except Exception:
                valid = False
                break
            converted.append((str(vals[0]), str(vals[1]), str(vals[2]), total_text))
        if valid and Counter(converted) == expected:
            without_explain = pattern.sub("", audit)
            assert normalize_sql(query) in normalize_sql(without_explain), \
                "The query passed to EXPLAIN QUERY PLAN was not also executed as the result query."
            return query

    raise AssertionError("No explained query both uses a ranking window function and computes the required paths.")


def verify_database(nodes, edges, original_case):
    assert os.path.isfile(DB_PATH), f"Database not created at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert "nodes" in tables, "Table 'nodes' is missing in the database."
    assert "edges" in tables, "Table 'edges' is missing in the database."

    if original_case:
        assert conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0] == 6
        assert conn.execute("SELECT COUNT(*) FROM edges").fetchone()[0] == 8

    assert [r[1] for r in conn.execute("PRAGMA table_info(nodes)")] == ["id", "name", "type"]
    assert [r[1] for r in conn.execute("PRAGMA table_info(edges)")] == ["source", "target", "amount", "timestamp"]

    expected_nodes = Counter((int(n["id"]), n["name"], n["type"]) for n in nodes)
    actual_nodes = Counter((int(r[0]), str(r[1]), str(r[2])) for r in conn.execute("SELECT id,name,type FROM nodes"))
    assert actual_nodes == expected_nodes, "The nodes table does not contain the CSV data exactly."

    expected_edges = Counter((int(e["source"]), int(e["target"]), Decimal(e["amount"]), int(e["timestamp"])) for e in edges)
    actual_edges = Counter((int(r[0]), int(r[1]), canonical_db_amount(r[2]), int(r[3])) for r in conn.execute("SELECT source,target,amount,timestamp FROM edges"))
    assert actual_edges == expected_edges, "The edges table does not contain the CSV data exactly."

    indexes = conn.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='edges'").fetchall()
    assert len(indexes) > 0, "No indexes found on the 'edges' table."
    indexed_columns = set()
    for (name,) in indexes:
        indexed_columns.update(r[2] for r in conn.execute(f'PRAGMA index_info("{name}")'))
    assert {"source", "target", "timestamp", "amount"} <= indexed_columns, \
        "Indexes do not cover source, target, timestamp, and amount."
    return conn


def run_case(nodes_text, edges_text, original_case=False):
    write_fixture(nodes_text, edges_text)
    nodes, edges = read_fixture()
    expected = expected_paths(nodes, edges)

    logdir = "/tmp/sqlite-audit-case"
    shutil.rmtree(logdir, ignore_errors=True)
    os.makedirs(logdir)
    for path in (DB_PATH, TOP_PATHS_CSV, QUERY_PLAN_TXT):
        if os.path.exists(path):
            os.remove(path)

    env = os.environ.copy()
    env["SQLITE_AUDIT_DIR"] = logdir
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, env=env)
    assert result.returncode == 0, f"Script execution failed with error:\n{result.stderr}"

    conn = verify_database(nodes, edges, original_case)

    assert os.path.isfile(TOP_PATHS_CSV), f"Output file not found: {TOP_PATHS_CSV}"
    with open(TOP_PATHS_CSV, newline="") as f:
        rows = [tuple(r) for r in csv.reader(f) if r]
    assert all(len(r) == 4 for r in rows), "top_paths.csv must contain four comma-separated fields per row."
    actual = Counter(rows)
    assert actual == expected, f"Incorrect output in {TOP_PATHS_CSV}. Expected {expected}, got {actual}"
    if original_case:
        assert set(",".join(r) for r in rows) == {
            "Alice,Diana,Eve,650", "Diana,Eve,Frank,1100"
        }

    assert os.path.isfile(QUERY_PLAN_TXT), f"Output file not found: {QUERY_PLAN_TXT}"
    plan_content = open(QUERY_PLAN_TXT, errors="replace").read()
    assert "SCAN" in plan_content.upper() or "SEARCH" in plan_content.upper(), \
        "query_plan.txt does not look like EXPLAIN QUERY PLAN output."

    audit = read_audit(logdir)
    query = find_analytical_query(audit, conn, expected)
    independently_explained = conn.execute("EXPLAIN QUERY PLAN " + query.rstrip().rstrip(";")).fetchall()
    details = [str(r[3]) for r in independently_explained]
    assert details and all(detail.upper() in plan_content.upper() for detail in details), \
        "query_plan.txt is not the EXPLAIN QUERY PLAN output for the executed analytical query."
    conn.close()


def test_complete_graph_processing():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found: {SCRIPT_PATH}"
    assert os.stat(SCRIPT_PATH).st_mode & stat.S_IXUSR, f"Script is not executable: {SCRIPT_PATH}"
    run_case(ORIGINAL_NODES, ORIGINAL_EDGES, original_case=True)
    run_case(DYNAMIC_NODES, DYNAMIC_EDGES, original_case=False)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
