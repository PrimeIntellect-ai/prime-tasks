#!/bin/bash
set -e
mkdir -p /logs/verifier

SQLITE_BIN=/usr/bin/sqlite3
REAL_SQLITE=/usr/bin/sqlite3.verifier-real
CAPTURE_LOG=/tmp/sqlite_verifier_calls.jsonl

mv "$SQLITE_BIN" "$REAL_SQLITE"
cat > "$SQLITE_BIN" <<'WRAPPER_EOF'
#!/usr/bin/python3
import json
import subprocess
import sys

REAL = "/usr/bin/sqlite3.verifier-real"
data = sys.stdin.buffer.read()
with open("/tmp/sqlite_verifier_calls.jsonl", "a", encoding="utf-8") as f:
    f.write(json.dumps({
        "argv": sys.argv[1:],
        "stdin": data.decode("utf-8", errors="replace")
    }) + "\n")
result = subprocess.run([REAL] + sys.argv[1:], input=data)
sys.exit(result.returncode)
WRAPPER_EOF
chmod +x "$SQLITE_BIN"
: > "$CAPTURE_LOG"

cleanup() {
    rm -f "$SQLITE_BIN"
    if [ -e "$REAL_SQLITE" ]; then
        mv "$REAL_SQLITE" "$SQLITE_BIN"
    fi
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
import uuid

DB_PATH = "/home/user/etl_graph.db"
SCRIPT_PATH = "/home/user/find_downstream.sh"
QUERY_PLAN_PATH = "/home/user/query_plan.txt"
CAPTURE_LOG = "/tmp/sqlite_verifier_calls.jsonl"
CAPTURED_SQL = "/tmp/captured_traversal.sql"


def run_script(*args, timeout=10):
    return subprocess.run(
        [SCRIPT_PATH, *args], capture_output=True, text=True, timeout=timeout
    )


def output_lines(result):
    return [line.strip() for line in result.stdout.strip().split("\n") if line.strip()]


def test_index_created():
    """Test that the index idx_dep_source was created on dependencies(source_id)."""
    assert os.path.isfile(DB_PATH), f"Database file not found at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_dep_source';")
    assert cursor.fetchone() is not None, "Index 'idx_dep_source' does not exist."

    cursor.execute("PRAGMA index_info('idx_dep_source');")
    index_info = cursor.fetchall()
    assert len(index_info) >= 1, "Index 'idx_dep_source' has no columns."
    column_names = [info[2] for info in index_info]
    assert column_names[0] == "source_id", \
        f"Index 'idx_dep_source' is not on 'source_id' column. Found: {column_names}"
    conn.close()


def test_script_exists_and_executable():
    """Test that the script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable."


def test_script_output_extract_users():
    """Test the output of the script for 'extract_users'."""
    expected_output = [
        "aggregate_metrics",
        "generate_reports",
        "join_data",
        "load_warehouse",
        "send_alerts",
        "transform_users",
    ]
    result = run_script("extract_users")
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    assert output_lines(result) == expected_output, \
        f"Expected {expected_output}, got {output_lines(result)}"


def test_script_output_extract_orders():
    """Test the output of the script for 'extract_orders' to ensure it handles arguments properly."""
    expected_output = [
        "aggregate_metrics",
        "generate_reports",
        "join_data",
        "load_warehouse",
        "send_alerts",
        "transform_orders",
    ]
    result = run_script("extract_orders")
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    assert output_lines(result) == expected_output, \
        f"Expected {expected_output}, got {output_lines(result)}"


def test_exactly_one_argument_required():
    no_arg = run_script()
    assert no_arg.returncode != 0, "Script must reject invocation with no arguments."

    two_args = run_script("extract_users", "extract_orders")
    assert two_args.returncode != 0, "Script must reject invocation with more than one argument."


def extract_single_recursive_sql(call):
    sources = list(call["argv"]) + [call["stdin"]]
    candidates = [s for s in sources if re.search(r"\bWITH\s+RECURSIVE\b", s, re.I)]
    assert len(candidates) == 1, \
        f"Expected one sqlite3 input containing a Recursive CTE, found {len(candidates)}."

    text = candidates[0]
    match = re.search(r"\bWITH\s+RECURSIVE\b", text, re.I)
    sql = text[match.start():].strip()

    conn = sqlite3.connect(DB_PATH)
    try:
        # execute() rejects multiple SQL statements, while accepting one trailing semicolon.
        explain_with_bindings(conn, sql)
    except sqlite3.Warning as exc:
        raise AssertionError(f"Traversal must contain exactly one SQL statement: {exc}")
    except sqlite3.ProgrammingError as exc:
        if "one statement" in str(exc).lower():
            raise AssertionError("Traversal must contain exactly one SQL statement.")
        raise
    finally:
        conn.close()
    return sql


def explain_with_bindings(conn, sql):
    statement = "EXPLAIN QUERY PLAN " + sql
    try:
        return conn.execute(statement).fetchall()
    except sqlite3.ProgrammingError as first_error:
        named = set(re.findall(r"(?<!:)[@:$]([A-Za-z_][A-Za-z0-9_]*)", sql))
        if named:
            return conn.execute(statement, {name: "extract_users" for name in named}).fetchall()

        numbered = [int(n) for n in re.findall(r"\?(\d+)", sql)]
        if numbered:
            count = max(numbered)
        else:
            count = len(re.findall(r"\?", sql))
        if count:
            return conn.execute(statement, tuple("extract_users" for _ in range(count))).fetchall()
        raise first_error


def test_dynamic_graph_safe_parameter_and_single_recursive_query():
    token = uuid.uuid4().hex
    start = f"probe_'\"; DROP TABLE tasks; --_{token}"
    names = [
        start,
        f"alpha_{token}",
        f"middle_{token}",
        f"zeta_{token}",
        f"unrelated_{token}",
    ]

    conn = sqlite3.connect(DB_PATH)
    try:
        base = conn.execute("SELECT COALESCE(MAX(id), 0) FROM tasks").fetchone()[0] + 100
        ids = {name: base + i for i, name in enumerate(names)}
        conn.executemany("INSERT INTO tasks(id, name) VALUES (?, ?)", [(ids[n], n) for n in names])
        edges = [
            (ids[start], ids[names[2]]),
            (ids[start], ids[names[1]]),
            (ids[names[2]], ids[names[3]]),
        ]
        conn.executemany("INSERT INTO dependencies(source_id, target_id) VALUES (?, ?)", edges)
        conn.commit()

        open(CAPTURE_LOG, "w").close()
        result = run_script(start)
        expected = sorted([names[1], names[2], names[3]])
        assert result.returncode == 0, f"Script failed on a safely quoted task name: {result.stderr}"
        assert output_lines(result) == expected, \
            f"Expected dynamically derived output {expected}, got {output_lines(result)}"

        assert conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='tasks'"
        ).fetchone(), "Unsafe parameter handling allowed SQL injection."

        with open(CAPTURE_LOG, encoding="utf-8") as f:
            calls = [json.loads(line) for line in f if line.strip()]
        assert len(calls) == 1, \
            f"Traversal must invoke sqlite3 once for one SQL query; observed {len(calls)} invocations."

        sql = extract_single_recursive_sql(calls[0])
        with open(CAPTURED_SQL, "w", encoding="utf-8") as f:
            f.write(sql)
    finally:
        conn.execute("DELETE FROM dependencies WHERE source_id >= ? OR target_id >= ?", (base, base))
        conn.execute("DELETE FROM tasks WHERE id >= ?", (base,))
        conn.commit()
        conn.close()


def test_query_plan_output():
    """Test that query_plan.txt is genuine output for the submitted Recursive CTE and uses the index."""
    assert os.path.isfile(QUERY_PLAN_PATH), f"Query plan file not found at {QUERY_PLAN_PATH}"
    with open(QUERY_PLAN_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "idx_dep_source" in content, "Query plan does not reference 'idx_dep_source'."
    assert os.path.isfile(CAPTURED_SQL), "No captured traversal SQL was available for plan validation."
    with open(CAPTURED_SQL, encoding="utf-8") as f:
        sql = f.read()

    conn = sqlite3.connect(DB_PATH)
    try:
        generated_rows = explain_with_bindings(conn, sql)
    finally:
        conn.close()
    generated_details = [row[3] for row in generated_rows]

    lines = [line.rstrip() for line in content.splitlines() if line.strip()]
    assert lines and lines[0].strip() == "QUERY PLAN", \
        "query_plan.txt is not raw sqlite3 EXPLAIN QUERY PLAN output."
    recorded_details = []
    for line in lines[1:]:
        match = re.match(r"^[| `]*--(.*)$", line)
        assert match, f"Invalid raw query-plan line: {line!r}"
        recorded_details.append(match.group(1).strip())

    assert recorded_details == generated_details, \
        "query_plan.txt does not match SQLite's plan for the submitted Recursive CTE."
    assert any("idx_dep_source" in detail for detail in generated_details), \
        "SQLite does not actually use idx_dep_source in the submitted Recursive CTE."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
