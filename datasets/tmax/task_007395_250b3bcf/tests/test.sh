#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import sqlite3
import subprocess
import shutil
import secrets

SCRIPT_PATH = "/home/user/analyze_fks.sh"
LOG_PATH = "/home/user/deadlock_risk.log"
DB_PATH = "/home/user/legacy_system.db"


def test_script_exists_and_executable():
    """Verify that the bash script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable by the user."


def get_sccs(graph):
    """Find strongly connected components using Tarjan's algorithm."""
    index_counter = [0]
    index = {}
    lowlink = {}
    stack = []
    on_stack = set()
    sccs = []

    def strongconnect(node):
        index[node] = index_counter[0]
        lowlink[node] = index_counter[0]
        index_counter[0] += 1
        stack.append(node)
        on_stack.add(node)

        for w in graph.get(node, []):
            if w not in index:
                strongconnect(w)
                lowlink[node] = min(lowlink[node], lowlink[w])
            elif w in on_stack:
                lowlink[node] = min(lowlink[node], index[w])

        if lowlink[node] == index[node]:
            scc = []
            while True:
                w = stack.pop()
                on_stack.remove(w)
                scc.append(w)
                if w == node:
                    break
            sccs.append(scc)

    for v in graph:
        if v not in index:
            strongconnect(v)

    return sccs


def expected_lines_from_database():
    """Derive expected cycles and row totals directly from the current database."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [row[0] for row in cursor.fetchall()]

    graph = {t: [] for t in tables}
    for t in tables:
        cursor.execute(f"PRAGMA foreign_key_list('{t}');")
        for fk in cursor.fetchall():
            ref_table = fk[2]
            if ref_table:
                graph[t].append(ref_table)

    sccs = get_sccs(graph)
    cycles = [
        scc for scc in sccs
        if len(scc) > 1 or (len(scc) == 1 and scc[0] in graph.get(scc[0], []))
    ]

    expected_lines = []
    for cycle in cycles:
        cycle_sorted = sorted(cycle)
        total_rows = 0
        for table in cycle:
            cursor.execute(f"SELECT COUNT(*) FROM {table};")
            total_rows += cursor.fetchone()[0]
        expected_lines.append(
            f"Cycle: {','.join(cycle_sorted)} | Total Rows: {total_rows}"
        )

    expected_lines.sort()
    conn.close()
    return expected_lines


def run_submission():
    if os.path.lexists(LOG_PATH):
        os.remove(LOG_PATH)

    result = subprocess.run(
        ["runuser", "-u", "user", "--", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(LOG_PATH), f"Log file not found at {LOG_PATH}"


def assert_log_matches(expected_lines):
    with open(LOG_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    actual_lines.sort()
    assert actual_lines == expected_lines, (
        f"Log file contents do not match expected results.\n"
        f"Expected:\n{expected_lines}\n"
        f"Got:\n{actual_lines}"
    )


def test_log_file_contents():
    """Execute the submitted script and verify the supplied database results."""
    expected_lines = expected_lines_from_database()
    run_submission()
    assert_log_matches(expected_lines)


def test_script_dynamically_analyzes_schema_and_rows():
    """Reject fixture-specific scripts using a fresh, unpredictable schema and data."""
    token = secrets.token_hex(5)
    names = [f"tbl_{token}_{letter}" for letter in "abcdefgh"]
    a, b, c, d, e, f, g, h = names
    counts = {name: secrets.randbelow(8) + 1 for name in names}

    backup_path = f"/tmp/legacy_system_backup_{token}.db"
    dynamic_path = f"/home/user/.legacy_system_dynamic_{token}.db"
    shutil.copy2(DB_PATH, backup_path)
    saved_log = None
    if os.path.isfile(LOG_PATH):
        with open(LOG_PATH, "rb") as log_file:
            saved_log = log_file.read()

    try:
        conn = sqlite3.connect(dynamic_path)
        cursor = conn.cursor()

        # One three-table SCC and one two-table SCC. The remaining tables are
        # acyclic and therefore must not appear in the output.
        cursor.execute(f"CREATE TABLE {a} (id INTEGER PRIMARY KEY, ref INTEGER REFERENCES {b}(id))")
        cursor.execute(f"CREATE TABLE {b} (id INTEGER PRIMARY KEY, ref INTEGER REFERENCES {c}(id))")
        cursor.execute(f"CREATE TABLE {c} (id INTEGER PRIMARY KEY, ref INTEGER REFERENCES {a}(id))")
        cursor.execute(f"CREATE TABLE {d} (id INTEGER PRIMARY KEY, ref INTEGER REFERENCES {e}(id))")
        cursor.execute(f"CREATE TABLE {e} (id INTEGER PRIMARY KEY, ref INTEGER REFERENCES {d}(id))")
        cursor.execute(f"CREATE TABLE {f} (id INTEGER PRIMARY KEY, ref INTEGER REFERENCES {g}(id))")
        cursor.execute(f"CREATE TABLE {g} (id INTEGER PRIMARY KEY)")
        cursor.execute(f"CREATE TABLE {h} (id INTEGER PRIMARY KEY)")

        for table, count in counts.items():
            cursor.executemany(
                f"INSERT INTO {table} (id, ref) VALUES (?, NULL)",
                [(i,) for i in range(1, count + 1)],
            )

        conn.commit()
        conn.close()
        os.chmod(dynamic_path, 0o644)
        os.replace(dynamic_path, DB_PATH)

        expected_lines = expected_lines_from_database()
        run_submission()
        assert_log_matches(expected_lines)
    finally:
        for path in (dynamic_path, DB_PATH + "-wal", DB_PATH + "-shm"):
            if os.path.lexists(path):
                os.remove(path)
        os.replace(backup_path, DB_PATH)

        if os.path.lexists(LOG_PATH):
            os.remove(LOG_PATH)
        if saved_log is not None:
            with open(LOG_PATH, "wb") as log_file:
                log_file.write(saved_log)
            os.chown(LOG_PATH, 1000, 1000)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
