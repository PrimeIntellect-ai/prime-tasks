#!/bin/bash
set +e
mkdir -p /logs/verifier

RUN_OK=1
TRACE_FILE=/tmp/sqlite_verifier_trace.log
STATUS_FILE=/tmp/analyze_graph_run_status
SQLITE_BIN=/usr/bin/sqlite3
SQLITE_REAL=/usr/bin/sqlite3.verifier-real
rm -f "$TRACE_FILE" "$STATUS_FILE"

# Prepare a fresh, unpredictable graph extension, restore the bad-index condition,
# and remove any outputs that may have been fabricated before verification.
python3 - <<'PY'
import os
import secrets
import sqlite3

path = "/home/user/dag.db"
conn = sqlite3.connect(path)
cur = conn.cursor()
cur.execute("SELECT id, duration FROM tasks")
rows = cur.fetchall()
assert rows and any(row[0] == 1 for row in rows), "tasks table or root task is missing"

# Add a verifier-generated root-to-leaf path whose value cannot be hardcoded in
# the submitted script. Its durations dominate the original graph.
scale = sum(abs(int(duration)) for _, duration in rows) + 1000
first_id = max(row[0] for row in rows) + 1
second_id = first_id + 1
first_duration = scale + secrets.randbelow(100000)
second_duration = scale + secrets.randbelow(100000)
cur.execute("INSERT INTO tasks(id, parent_id, duration) VALUES (?, 1, ?)",
            (first_id, first_duration))
cur.execute("INSERT INTO tasks(id, parent_id, duration) VALUES (?, ?, ?)",
            (second_id, first_id, second_duration))

# Require the submitted script itself to perform the requested index repair.
cur.execute("DROP INDEX IF EXISTS idx_parent_id")
cur.execute("DROP INDEX IF EXISTS idx_parent")
cur.execute("CREATE INDEX idx_parent ON tasks(duration)")
conn.commit()
conn.close()

for output in ("/home/user/critical_path.txt", "/home/user/plan.txt"):
    try:
        os.remove(output)
    except FileNotFoundError:
        pass
os.chmod(path, 0o666)
PY
if [ $? -ne 0 ]; then
    RUN_OK=0
fi

# Interpose sqlite3 while the artifact runs. This records the SQL actually sent
# to SQLite and its stdout, including the real EXPLAIN QUERY PLAN result.
if [ "$RUN_OK" -eq 1 ] && [ -x "$SQLITE_BIN" ]; then
    mv "$SQLITE_BIN" "$SQLITE_REAL"
    if [ $? -ne 0 ]; then
        RUN_OK=0
    else
        cat > "$SQLITE_BIN" <<'WRAPPER'
#!/bin/bash
REAL=/usr/bin/sqlite3.verifier-real
LOG=/tmp/sqlite_verifier_trace.log
IN=$(mktemp)
OUT=$(mktemp)
cat > "$IN"
{
    echo '=== SQLITE CALL ==='
    echo '--- ARGS ---'
    printf '%s\n' "$@"
    echo '--- STDIN ---'
    cat "$IN"
} >> "$LOG"
"$REAL" "$@" < "$IN" > "$OUT"
status=$?
{
    echo '--- STDOUT ---'
    cat "$OUT"
    echo '=== END SQLITE CALL ==='
} >> "$LOG"
cat "$OUT"
rm -f "$IN" "$OUT"
exit "$status"
WRAPPER
        chmod 755 "$SQLITE_BIN"
        touch "$TRACE_FILE"
        chmod 666 "$TRACE_FILE"

        chmod a+rx /home/user/analyze_graph.sh 2>/dev/null
        timeout 30s runuser -u user -- env HOME=/home/user PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /home/user/analyze_graph.sh
        if [ $? -ne 0 ]; then
            RUN_OK=0
        fi

        rm -f "$SQLITE_BIN"
        mv "$SQLITE_REAL" "$SQLITE_BIN"
    fi
else
    RUN_OK=0
fi

# Ensure sqlite3 is restored even if wrapper installation or execution failed.
if [ -e "$SQLITE_REAL" ]; then
    rm -f "$SQLITE_BIN"
    mv "$SQLITE_REAL" "$SQLITE_BIN"
fi
printf '%s\n' "$RUN_OK" > "$STATUS_FILE"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3

DB_PATH = "/home/user/dag.db"
SCRIPT_PATH = "/home/user/analyze_graph.sh"
CRITICAL_PATH_TXT = "/home/user/critical_path.txt"
PLAN_TXT = "/home/user/plan.txt"
TRACE_FILE = "/tmp/sqlite_verifier_trace.log"
STATUS_FILE = "/tmp/analyze_graph_run_status"


def test_script_was_executed_successfully():
    assert os.path.isfile(STATUS_FILE), "Verifier could not execute the submitted script."
    with open(STATUS_FILE) as f:
        assert f.read().strip() == "1", "The submitted script failed or timed out when executed."


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "sqlite3" in content, "The script does not appear to invoke sqlite3."
    first_line = content.splitlines()[0] if content.splitlines() else ""
    assert re.search(r"bash", first_line, re.I), "The submitted artifact is not a Bash script."


def test_recursive_cte_and_explain_were_actually_executed():
    assert os.path.isfile(TRACE_FILE), "No sqlite3 execution trace was produced."
    with open(TRACE_FILE, "r", errors="replace") as f:
        trace = f.read()

    assert re.search(r"\bWITH\s+RECURSIVE\b", trace, re.I), \
        "The executed sqlite3 commands did not contain a recursive CTE."
    assert re.search(r"\bEXPLAIN\s+QUERY\s+PLAN\b", trace, re.I), \
        "The script did not execute EXPLAIN QUERY PLAN."
    assert re.search(r"\btasks\b", trace, re.I), \
        "The executed recursive query did not reference the tasks table."
    assert re.search(r"\bparent_id\b", trace, re.I), \
        "The executed SQL did not perform the required hierarchical traversal."


def test_database_indexes():
    assert os.path.isfile(DB_PATH), f"Database file missing at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='tasks'")
    indexes = {row[0]: row[1] for row in cursor.fetchall()}

    assert "idx_parent" not in indexes, "The old corrupted index 'idx_parent' was not dropped."
    assert "idx_parent_id" in indexes, "The new index 'idx_parent_id' was not created."

    # Verify the index is actually on parent_id
    sql = indexes["idx_parent_id"].lower()
    assert "parent_id" in sql, f"The new index 'idx_parent_id' does not seem to index 'parent_id'. SQL: {sql}"

    cursor.execute("PRAGMA index_info('idx_parent_id')")
    indexed_columns = [row[2] for row in cursor.fetchall()]
    conn.close()
    assert indexed_columns == ["parent_id"], \
        f"idx_parent_id must index exactly parent_id, but indexes {indexed_columns}."


def test_critical_path_output():
    assert os.path.isfile(DB_PATH), f"Database file missing at {DB_PATH}"

    # Compute the expected critical path dynamically from the database
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT id, parent_id, duration FROM tasks")
    rows = cursor.fetchall()
    conn.close()

    tree = {}
    durations = {}
    for tid, pid, dur in rows:
        durations[tid] = dur
        if pid not in tree:
            tree[pid] = []
        tree[pid].append(tid)

    def get_max_path(node):
        if node not in tree:
            return durations[node]
        return durations[node] + max(get_max_path(child) for child in tree[node])

    roots = tree.get(None, [])
    expected_max = max(get_max_path(r) for r in roots) if roots else 0

    assert os.path.isfile(CRITICAL_PATH_TXT), f"Output file {CRITICAL_PATH_TXT} does not exist."

    with open(CRITICAL_PATH_TXT, "r") as f:
        content = f.read().strip()

    expected_str = f"Critical Path Length: {expected_max}"
    assert content == expected_str, f"Expected '{expected_str}', but got '{content}'."


def test_query_plan_output():
    assert os.path.isfile(PLAN_TXT), f"Plan output file {PLAN_TXT} does not exist."

    with open(PLAN_TXT, "r") as f:
        content = f.read()

    assert "idx_parent_id" in content, "The EXPLAIN QUERY PLAN output in plan.txt does not reference the new index 'idx_parent_id'."
    assert re.search(r"QUERY PLAN|CO-ROUTINE|RECURSIVE", content, re.I), \
        "plan.txt does not look like SQLite EXPLAIN QUERY PLAN output for a recursive query."

    # The plan must have been emitted by sqlite3 during this execution, rather
    # than being a pre-existing or independently fabricated text file.
    with open(TRACE_FILE, "r", errors="replace") as f:
        trace = f.read()
    assert content.strip() and content.strip() in trace, \
        "plan.txt was not generated from sqlite3 output produced by the script."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
