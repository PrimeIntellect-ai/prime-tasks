#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import random
import re
import secrets
import stat
import sqlite3
import subprocess

DB_PATH = "/home/user/routes.db"
OPTIMIZE_SQL_PATH = "/home/user/optimize.sql"
SCRIPT_PATH = "/home/user/get_reachable.sh"


def parse_optimize_sql():
    """Execute the submitted statement on a fresh schema and return its index definition."""
    with open(OPTIMIZE_SQL_PATH, "r", encoding="utf-8") as f:
        sql = f.read()
    assert sql.strip(), "optimize.sql is empty"

    conn = sqlite3.connect(":memory:")
    try:
        conn.execute("CREATE TABLE edges (source TEXT, target TEXT, cost INTEGER)")
        # execute(), unlike executescript(), rejects additional SQL statements.
        conn.execute(sql)
        indices = conn.execute("PRAGMA index_list('edges')").fetchall()
        assert len(indices) == 1, "optimize.sql must contain exactly one CREATE INDEX statement for edges"
        index_name = indices[0][1]
        assert indices[0][2] == 0, "The routing index must not be UNIQUE"
        if len(indices[0]) > 4:
            assert indices[0][4] == 0, "The routing index must not be partial"
        columns = [row[2] for row in conn.execute(
            "PRAGMA index_info(" + repr(index_name) + ")"
        ).fetchall()]
        assert columns and columns[0] == "source", \
            "The index in optimize.sql must have source as its first column"
        assert len(columns) == len(set(columns)), "The index contains duplicate columns"
        assert all(c in {"source", "target", "cost"} for c in columns), \
            "The routing index may only contain columns from edges"
        return index_name, columns
    except sqlite3.Error as exc:
        raise AssertionError(f"optimize.sql is not one valid CREATE INDEX statement: {exc}")
    finally:
        conn.close()


def test_optimize_sql_exists():
    """Test that optimize.sql exists."""
    assert os.path.isfile(OPTIMIZE_SQL_PATH), f"File missing: {OPTIMIZE_SQL_PATH}"


def test_optimize_sql_is_required_index_statement():
    """Test that optimize.sql actually contains the requested source index statement."""
    parse_optimize_sql()


def test_index_applied():
    """Test that an index was created on the edges table."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA index_list('edges');")
    indices = cursor.fetchall()
    conn.close()
    assert len(indices) >= 1, "No index found on the 'edges' table."


def test_optimize_sql_was_applied():
    """Test that the index described by optimize.sql exists in routes.db."""
    expected_name, expected_columns = parse_optimize_sql()
    conn = sqlite3.connect(DB_PATH)
    try:
        indices = conn.execute("PRAGMA index_list('edges')").fetchall()
        matching = [row for row in indices if row[1] == expected_name]
        assert matching, f"Index {expected_name!r} from optimize.sql was not applied to routes.db"
        assert matching[0][2] == 0, "Applied routing index must not be UNIQUE"
        if len(matching[0]) > 4:
            assert matching[0][4] == 0, "Applied routing index must not be partial"
        actual_columns = [row[2] for row in conn.execute(
            "PRAGMA index_info(" + repr(expected_name) + ")"
        ).fetchall()]
        assert actual_columns == expected_columns, \
            "The applied index does not match the index in optimize.sql"
    finally:
        conn.close()


def test_query_plan_optimized():
    """Test that the recursive query uses an index instead of a full table scan."""
    query = """
    EXPLAIN QUERY PLAN
    WITH RECURSIVE paths(node, total_cost) AS (
        SELECT 'A', 0
        UNION ALL
        SELECT e.target, p.total_cost + e.cost
        FROM paths p
        JOIN edges e ON p.node = e.source
        WHERE p.total_cost + e.cost <= 50
    )
    SELECT node, MIN(total_cost) as min_cost 
    FROM paths 
    GROUP BY node 
    ORDER BY node;
    """
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute(query)
    plan = cursor.fetchall()
    conn.close()

    plan_text = " ".join([row[-1] for row in plan]).upper()

    # It should not do a full table scan on edges
    assert "SCAN TABLE EDGES" not in plan_text and "SCAN EDGES" not in plan_text, \
        "The query plan still shows a full table scan on the 'edges' table."

    # It should use an index
    assert "SEARCH TABLE EDGES USING" in plan_text or "SEARCH EDGES USING" in plan_text, \
        "The query plan does not show an index search on the 'edges' table."


def test_script_exists_and_executable():
    """Test that the bash script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script missing: {SCRIPT_PATH}"
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script is not executable: {SCRIPT_PATH}"


def test_script_contains_dynamic_recursive_sqlite_query():
    """Test that the Bash artifact invokes SQLite with a recursive query and its argument."""
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        script = f.read()
    assert re.search(r"\bsqlite3\b", script), "Script does not invoke sqlite3"
    assert re.search(r"\bWITH\s+RECURSIVE\b", script, re.IGNORECASE), \
        "Script does not contain the required recursive CTE"
    assert "/home/user/routes.db" in script, "Script does not query /home/user/routes.db"
    assert re.search(r"\$(?:1\b|\{1\})", script), \
        "Script does not dynamically use its first command-line argument"


def test_script_output_A():
    """Test the bash script output for starting node A."""
    result = subprocess.run([SCRIPT_PATH, "A"], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with return code {result.returncode}"

    expected_output = "A:0\nB:10\nC:20\nD:25\n"
    assert result.stdout.strip() == expected_output.strip(), \
        f"Incorrect output for starting node 'A'.\nExpected:\n{expected_output.strip()}\nGot:\n{result.stdout.strip()}"


def test_script_output_C():
    """Test the bash script output for starting node C."""
    result = subprocess.run([SCRIPT_PATH, "C"], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with return code {result.returncode}"

    expected_output = "C:0\nD:5\nE:35\nF:45\n"
    assert result.stdout.strip() == expected_output.strip(), \
        f"Incorrect output for starting node 'C'.\nExpected:\n{expected_output.strip()}\nGot:\n{result.stdout.strip()}"


def test_script_on_fresh_dynamic_graph():
    """Exercise argument substitution and traversal on verifier-generated data."""
    prefix = "V" + secrets.token_hex(8)
    nodes = [f"{prefix}_{i}" for i in range(7)]
    rng = random.SystemRandom()
    c1, c2, c3, c4 = [rng.randint(2, 9) for _ in range(4)]
    edges = [
        (nodes[0], nodes[1], c1),
        (nodes[0], nodes[2], c1 + c2 + rng.randint(2, 7)),
        (nodes[1], nodes[2], c2),
        (nodes[1], nodes[3], c3 + rng.randint(4, 10)),
        (nodes[2], nodes[3], c3),
        (nodes[3], nodes[4], c4),
        (nodes[0], nodes[5], 49),
        (nodes[5], nodes[6], 2),
    ]

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executemany("INSERT INTO edges(source, target, cost) VALUES (?, ?, ?)", edges)
        conn.commit()
    finally:
        conn.close()

    adjacency = {}
    for source, target, cost in edges:
        adjacency.setdefault(source, []).append((target, cost))

    distances = {nodes[0]: 0}
    queue = [(0, nodes[0])]
    while queue:
        total, node = heapq.heappop(queue)
        if total != distances[node]:
            continue
        for target, cost in adjacency.get(node, []):
            candidate = total + cost
            if candidate <= 50 and candidate < distances.get(target, 10**9):
                distances[target] = candidate
                heapq.heappush(queue, (candidate, target))

    expected = "\n".join(f"{node}:{distances[node]}" for node in sorted(distances))
    result = subprocess.run(
        [SCRIPT_PATH, nodes[0]], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, \
        f"Script failed for a dynamically generated starting node: {result.stderr}"
    assert result.stdout.strip() == expected, \
        f"Incorrect dynamic traversal output.\nExpected:\n{expected}\nGot:\n{result.stdout.strip()}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
