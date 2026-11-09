#!/bin/bash
set -e
mkdir -p /logs/verifier

SQLITE_BIN="$(command -v sqlite3)"
REAL_SQLITE="${SQLITE_BIN}.verifier-real.$$.$RANDOM"
TRACE_DIR="$(mktemp -d /tmp/sqlite-trace.XXXXXX)"
mv "$SQLITE_BIN" "$REAL_SQLITE"

cleanup() {
    rm -f "$SQLITE_BIN"
    if [ -e "$REAL_SQLITE" ]; then
        mv "$REAL_SQLITE" "$SQLITE_BIN"
    fi
    rm -rf "$TRACE_DIR"
}
trap cleanup EXIT

cat > "$SQLITE_BIN" <<EOF
#!/bin/bash
TRACE_DIR=$(printf '%q' "$TRACE_DIR")
REAL_SQLITE=$(printf '%q' "$REAL_SQLITE")
CSV_PATH=/home/user/materialized_graph.csv
record=\$(mktemp "\$TRACE_DIR/invocation.XXXXXX")
printf '%s\\0' "\$@" > "\${record}.args"
cat > "\${record}.stdin"
if [ -e "\$CSV_PATH" ]; then
    stat -c '%s' "\$CSV_PATH" > "\${record}.pre_size"
else
    echo -1 > "\${record}.pre_size"
fi
set -o pipefail
"\$REAL_SQLITE" "\$@" < "\${record}.stdin" | tee "\${record}.stdout"
rc=\${PIPESTATUS[0]}
if [ -f "\$CSV_PATH" ]; then
    cp "\$CSV_PATH" "\${record}.csv"
fi
exit "\$rc"
EOF
chmod +x "$SQLITE_BIN"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import re
import sqlite3
import subprocess

SCRIPT_PATH = "/home/user/run_query.sh"
CSV_PATH = "/home/user/materialized_graph.csv"
DB_PATH = "/home/user/tasks.db"
TRACE_DIR = os.environ["TRACE_DIR"]

ORIGINAL_ROWS = [
    (1, None, 'Project A', 10),
    (2, 1, 'Task A1', 5),
    (3, 1, 'Task A2', 8),
    (4, 2, 'Subtask A1.1', 3),
    (5, 2, 'Subtask A1.2', 7),
    (6, None, 'Project B', 15),
    (7, 6, 'Task B1', 4),
    (8, 7, 'Subtask B1.1', 6),
    (9, 6, 'Task B2', 5),
    (10, 3, 'Subtask A2.1', 2),
]

DYNAMIC_CASES = [
    [
        (41, None, 'Root X', 3),
        (7, 41, 'Child X1', 20),
        (90, 7, 'Grandchild X', -4),
        (12, 41, 'Child X2', 16),
        (300, None, 'Root Y', 25),
        (2, 300, 'Child Y1', 0),
        (88, 2, 'Grandchild Y', 11),
    ],
    [
        (105, None, 'Alpha', -2),
        (9, 105, 'A', 8),
        (77, 9, 'B', 8),
        (4, 77, 'C', 8),
        (222, 105, 'D', 24),
        (18, None, 'Beta', 6),
        (63, 18, 'E', 1),
        (500, 18, 'F', 1),
        (31, 500, 'G', 1),
    ],
]


def install_database(rows):
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    con = sqlite3.connect(DB_PATH)
    try:
        con.execute("CREATE TABLE tasks (id INTEGER PRIMARY KEY, parent_id INTEGER, name TEXT, duration INTEGER)")
        con.executemany("INSERT INTO tasks (id, parent_id, name, duration) VALUES (?, ?, ?, ?)", rows)
        con.commit()
    finally:
        con.close()


def expected_for(rows):
    by_parent = {}
    by_id = {}
    for task_id, parent_id, name, duration in rows:
        by_id[task_id] = (parent_id, duration)
        by_parent.setdefault(parent_id, []).append(task_id)

    projected = []
    def visit(task_id, root_id, depth, total):
        duration = by_id[task_id][1]
        path_duration = total + duration
        projected.append([task_id, root_id, depth, path_duration, None])
        for child in by_parent.get(task_id, []):
            visit(child, root_id, depth + 1, path_duration)

    for root in by_parent.get(None, []):
        visit(root, root, 0, 0)

    groups = {}
    for row in projected:
        groups.setdefault(row[1], []).append(row)
    for group in groups.values():
        ordered = sorted(group, key=lambda row: (-row[3], row[0]))
        previous_key = None
        previous_rank = None
        for position, row in enumerate(ordered, 1):
            key = (-row[3], row[0])
            if key != previous_key:
                previous_rank = position
                previous_key = key
            row[4] = previous_rank

    projected.sort(key=lambda row: row[0])
    return [['id', 'root_id', 'depth', 'path_duration', 'rank_in_root']] + [
        [str(value) for value in row] for row in projected
    ]


def clear_trace():
    for path in glob.glob(os.path.join(TRACE_DIR, 'invocation.*')):
        os.remove(path)


def run_and_validate(rows):
    install_database(rows)
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    clear_trace()

    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with exit code {result.returncode}. stderr: {result.stderr}"
    assert os.path.isfile(CSV_PATH), f"Output CSV not found at {CSV_PATH} after running the script"

    argument_logs = glob.glob(os.path.join(TRACE_DIR, 'invocation.*.args'))
    assert len(argument_logs) == 1, f"Expected exactly one sqlite3 invocation, observed {len(argument_logs)}"
    base = argument_logs[0][:-5]

    with open(argument_logs[0], 'rb') as f:
        arguments = [part.decode('utf-8', 'replace') for part in f.read().split(b'\0') if part]
    with open(base + '.stdin', 'r', encoding='utf-8', errors='replace') as f:
        stdin_sql = f.read()
    submitted_sql = stdin_sql + '\n' + '\n'.join(arguments)

    assert re.search(r'\bWITH\s+RECURSIVE\b', submitted_sql, re.IGNORECASE), \
        "The sqlite3 invocation did not execute a WITH RECURSIVE query"
    assert re.search(r'\bRANK\s*\(\s*\)\s*OVER\s*\(', submitted_sql, re.IGNORECASE), \
        "The sqlite3 invocation did not use the required RANK() window function"
    assert not re.search(r'\bCREATE\s+(?:TEMP(?:ORARY)?\s+)?TABLE\b', submitted_sql, re.IGNORECASE), \
        "The query must not create temporary or other helper tables"

    with open(base + '.pre_size', 'r', encoding='utf-8') as f:
        pre_size = int(f.read().strip())
    assert pre_size in (-1, 0), "The CSV was populated before sqlite3 was invoked"
    assert os.path.isfile(base + '.csv'), "The sqlite3 invocation did not materialize the output CSV"
    with open(base + '.csv', 'rb') as f:
        during_sqlite = f.read()
    with open(CSV_PATH, 'rb') as f:
        final_bytes = f.read()
    assert during_sqlite == final_bytes, "The final CSV was replaced or modified after sqlite3 finished"

    with open(CSV_PATH, 'r', newline='') as f:
        actual_csv = list(csv.reader(f))
    return actual_csv


def test_script_exists_and_executable():
    """Check if the run_query.sh script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_script_produces_correct_csv():
    """Run the script and verify the resulting CSV matches the expected output exactly."""
    actual_csv = run_and_validate(ORIGINAL_ROWS)
    expected_csv = [
        ['id', 'root_id', 'depth', 'path_duration', 'rank_in_root'],
        ['1', '1', '0', '10', '6'],
        ['2', '1', '1', '15', '5'],
        ['3', '1', '1', '18', '3'],
        ['4', '1', '2', '18', '4'],
        ['5', '1', '2', '22', '1'],
        ['6', '6', '0', '15', '4'],
        ['7', '6', '1', '19', '3'],
        ['8', '6', '2', '25', '1'],
        ['9', '6', '1', '20', '2'],
        ['10', '1', '2', '20', '2']
    ]
    assert actual_csv == expected_csv, "CSV contents do not match the expected schema or data."


def test_query_generalizes_to_changed_graphs():
    for rows in DYNAMIC_CASES:
        actual_csv = run_and_validate(rows)
        assert actual_csv == expected_for(rows), "CSV is incorrect for a changed task graph"
TEST_EOF

if TRACE_DIR="$TRACE_DIR" python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
