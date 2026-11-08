#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'WRAP_EOF' > /tmp/sqlite_trace_wrap.c
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void clean_sql(char *dst, size_t n, const char *src) {
    size_t j = 0;
    if (!src) src = "";
    while (*src && j + 1 < n) {
        char c = *src++;
        dst[j++] = (c == '\n' || c == '\r' || c == '\t') ? ' ' : c;
    }
    dst[j] = 0;
}

static void log_line(const char *kind, void *ptr, int rc, const char *sql) {
    const char *path = getenv("SQLITE_TRACE_FILE");
    if (!path) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    char buf[8192];
    clean_sql(buf, sizeof(buf), sql);
    fprintf(f, "%s\t%p\t%d\t%s\n", kind, ptr, rc, buf);
    fclose(f);
}

int __real_sqlite3_prepare_v2(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
int __wrap_sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    int rc = __real_sqlite3_prepare_v2(db, sql, n, stmt, tail);
    log_line("PREP", stmt ? (void *)*stmt : NULL, rc, sql);
    return rc;
}

int __real_sqlite3_exec(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **);
int __wrap_sqlite3_exec(sqlite3 *db, const char *sql,
                        int (*cb)(void *, int, char **, char **), void *arg, char **err) {
    int rc = __real_sqlite3_exec(db, sql, cb, arg, err);
    log_line("EXEC", NULL, rc, sql);
    return rc;
}

int __real_sqlite3_bind_int(sqlite3_stmt *, int, int);
int __wrap_sqlite3_bind_int(sqlite3_stmt *s, int i, int v) {
    int rc = __real_sqlite3_bind_int(s, i, v);
    log_line("BIND", s, rc, "int");
    return rc;
}

int __real_sqlite3_bind_int64(sqlite3_stmt *, int, sqlite3_int64);
int __wrap_sqlite3_bind_int64(sqlite3_stmt *s, int i, sqlite3_int64 v) {
    int rc = __real_sqlite3_bind_int64(s, i, v);
    log_line("BIND", s, rc, "int64");
    return rc;
}

int __real_sqlite3_bind_text(sqlite3_stmt *, int, const char *, int, void (*)(void *));
int __wrap_sqlite3_bind_text(sqlite3_stmt *s, int i, const char *v, int n, void (*d)(void *)) {
    int rc = __real_sqlite3_bind_text(s, i, v, n, d);
    log_line("BIND", s, rc, "text");
    return rc;
}

int __real_sqlite3_step(sqlite3_stmt *);
int __wrap_sqlite3_step(sqlite3_stmt *s) {
    int rc = __real_sqlite3_step(s);
    log_line("STEP", s, rc, "");
    return rc;
}
WRAP_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import subprocess

DB = "/home/user/etl.db"
SRC = "/home/user/graph_etl.c"
PLAN = "/home/user/plan.txt"
BIN = "/tmp/graph_etl_verified"
TRACE = "/tmp/graph_etl_sqlite_trace.log"


def test_c_file_exists_and_content():
    """Retain the original source-level transaction and parameterization assertions."""
    assert os.path.exists(SRC), f"C source file {SRC} does not exist."
    with open(SRC, "r", encoding="utf-8") as f:
        content = f.read()

    has_immediate = re.search(r"BEGIN\s+IMMEDIATE", content, re.IGNORECASE)
    has_exclusive = re.search(r"BEGIN\s+EXCLUSIVE", content, re.IGNORECASE)
    assert has_immediate or has_exclusive, (
        "C code does not use 'BEGIN IMMEDIATE' or 'BEGIN EXCLUSIVE'."
    )
    assert "sqlite3_bind_" in content, (
        "C code does not use parameterized queries (missing sqlite3_bind_...)."
    )


def test_original_fixed_results():
    """Retain the original result and uniqueness checks for 1, 5, and 10."""
    assert os.path.exists(DB), f"Database file {DB} does not exist."
    conn = sqlite3.connect(DB)
    try:
        cur = conn.cursor()
        cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='fof_graph'")
        assert cur.fetchone() is not None, "Table 'fof_graph' does not exist in etl.db."
        cur.execute("""
            SELECT DISTINCT a.user_a, b.user_b
            FROM user_connections a
            JOIN user_connections b ON a.user_b = b.user_a
            WHERE a.user_a IN (1, 5, 10) AND a.user_a != b.user_b
            ORDER BY a.user_a, b.user_b
        """)
        expected = cur.fetchall()
        cur.execute("""
            SELECT DISTINCT source, target FROM fof_graph
            WHERE source IN (1, 5, 10) ORDER BY source, target
        """)
        assert cur.fetchall() == expected

        cur.execute("PRAGMA index_list('fof_graph')")
        indexes = cur.fetchall()
        assert any(row[2] == 1 for row in indexes), (
            "Table 'fof_graph' does not have a UNIQUE constraint."
        )
        exact_pair_unique = False
        for row in indexes:
            if row[2] != 1:
                continue
            name = row[1].replace('"', '""')
            cols = [r[2] for r in conn.execute(f'PRAGMA index_info("{name}")')]
            if cols == ["source", "target"]:
                exact_pair_unique = True
        assert exact_pair_unique, "UNIQUE constraint is not on exactly (source, target)."
    finally:
        conn.close()


def parse_trace(path):
    events = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t", 3)
            assert len(parts) == 4, f"Malformed trace line: {line!r}"
            events.append({"kind": parts[0], "ptr": parts[1],
                           "rc": int(parts[2]), "sql": parts[3]})
    return events


def test_compile_execute_arbitrary_arguments_and_runtime_requirements():
    """Compile the submitted source and exercise unseen IDs while tracing SQLite API use."""
    subprocess.run([
        "gcc", "-O2", SRC, "/tmp/sqlite_trace_wrap.c", "-o", BIN,
        "-lsqlite3",
        "-Wl,--wrap=sqlite3_prepare_v2",
        "-Wl,--wrap=sqlite3_exec",
        "-Wl,--wrap=sqlite3_bind_int",
        "-Wl,--wrap=sqlite3_bind_int64",
        "-Wl,--wrap=sqlite3_bind_text",
        "-Wl,--wrap=sqlite3_step",
    ], check=True, capture_output=True, text=True)

    conn = sqlite3.connect(DB)
    try:
        # Remove all submitted indexes on the raw table. The executed program must recreate one.
        raw_indexes = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='user_connections' "
            "AND sql IS NOT NULL"
        ).fetchall()
        for (name,) in raw_indexes:
            conn.execute('DROP INDEX "' + name.replace('"', '""') + '"')

        maximum = conn.execute(
            "SELECT COALESCE(MAX(x), 0) FROM (SELECT user_a x FROM user_connections "
            "UNION ALL SELECT user_b FROM user_connections)"
        ).fetchone()[0]
        base = int(maximum) + 1000
        sources = [base, base + 10, base + 20, base + 30]
        edges = []
        for i, source in enumerate(sources):
            middle1 = base + 100 + i * 10
            middle2 = middle1 + 1
            target1 = base + 500 + i * 10
            target2 = target1 + 1
            # Duplicate target through two paths plus a length-two self path.
            edges.extend([
                (source, middle1), (source, middle2),
                (middle1, target1), (middle1, target2),
                (middle2, target2), (middle2, source),
            ])
        conn.executemany("INSERT INTO user_connections(user_a,user_b) VALUES (?,?)", edges)
        conn.executemany("DELETE FROM fof_graph WHERE source=?", [(s,) for s in sources])
        conn.commit()
    finally:
        conn.close()

    if os.path.exists(TRACE):
        os.unlink(TRACE)
    env = os.environ.copy()
    env["SQLITE_TRACE_FILE"] = TRACE
    result = subprocess.run(
        [BIN] + [str(s) for s in sources], env=env, timeout=20,
        capture_output=True, text=True
    )
    assert result.returncode == 0, (
        f"Compiled program failed for arbitrary arguments.\nstdout={result.stdout}\n"
        f"stderr={result.stderr}"
    )
    assert os.path.exists(TRACE), "No SQLite API activity was observed from the program."

    conn = sqlite3.connect(DB)
    try:
        placeholders = ",".join("?" for _ in sources)
        expected = conn.execute(f"""
            SELECT DISTINCT a.user_a, b.user_b
            FROM user_connections a
            JOIN user_connections b ON a.user_b=b.user_a
            WHERE a.user_a IN ({placeholders}) AND a.user_a != b.user_b
            ORDER BY a.user_a,b.user_b
        """, sources).fetchall()
        actual = conn.execute(f"""
            SELECT source,target FROM fof_graph
            WHERE source IN ({placeholders}) ORDER BY source,target
        """, sources).fetchall()
        assert actual == expected, (
            f"Program produced wrong results for arbitrary IDs.\nExpected: {expected}\nActual: {actual}"
        )

        qualifying = []
        for row in conn.execute("PRAGMA index_list('user_connections')"):
            name = row[1]
            quoted = name.replace('"', '""')
            cols = [r[2] for r in conn.execute(f'PRAGMA index_info("{quoted}")')]
            if cols and cols[0] == "user_a":
                qualifying.append(name)
        assert qualifying, (
            "Executing the program did not create an index on user_connections beginning with user_a."
        )

        runtime_plan = conn.execute("""
            EXPLAIN QUERY PLAN
            SELECT b.user_b FROM user_connections a
            JOIN user_connections b ON a.user_b=b.user_a
            WHERE a.user_a=?
        """, (sources[0],)).fetchall()
        runtime_details = "\n".join(str(r[3]) for r in runtime_plan)
        assert re.search(r"USING\s+(?:COVERING\s+)?INDEX", runtime_details, re.I), (
            f"SQLite does not actually use the created index:\n{runtime_details}"
        )
    finally:
        conn.close()

    events = parse_trace(TRACE)
    prepared_sql = {}
    prepare_count = {}
    bind_count = {}
    step_count = {}
    semantic_events = []

    for pos, event in enumerate(events):
        kind, ptr, rc, sql = event["kind"], event["ptr"], event["rc"], event["sql"]
        if kind == "PREP" and rc == 0:
            prepared_sql[ptr] = sql
            prepare_count[ptr] = prepare_count.get(ptr, 0) + 1
        elif kind == "BIND" and rc == 0:
            bind_count[ptr] = bind_count.get(ptr, 0) + 1
        elif kind == "STEP":
            step_count[ptr] = step_count.get(ptr, 0) + 1
            stmt_sql = prepared_sql.get(ptr, "")
            if re.match(r"^\s*(BEGIN\s+(?:IMMEDIATE|EXCLUSIVE)|COMMIT)\b", stmt_sql, re.I):
                semantic_events.append((pos, stmt_sql))
        elif kind == "EXEC" and rc == 0:
            if re.match(r"^\s*(BEGIN\s+(?:IMMEDIATE|EXCLUSIVE)|COMMIT)\b", sql, re.I):
                semantic_events.append((pos, sql))

    candidates = []
    for ptr, sql in prepared_sql.items():
        if ("?" in sql and prepare_count.get(ptr) == 1
                and bind_count.get(ptr, 0) >= len(sources)
                and step_count.get(ptr, 0) >= len(sources)
                and re.search(r"user_connections|fof_graph", sql, re.I)):
            candidates.append(ptr)
    assert candidates, (
        "No graph-related parameterized statement was prepared once and reused across all arguments."
    )

    begin_positions = [p for p, sql in semantic_events
                       if re.match(r"^\s*BEGIN\s+(?:IMMEDIATE|EXCLUSIVE)\b", sql, re.I)]
    commit_positions = [p for p, sql in semantic_events
                        if re.match(r"^\s*COMMIT\b", sql, re.I)]
    assert begin_positions and commit_positions, (
        "The executed program did not successfully run BEGIN IMMEDIATE/EXCLUSIVE and COMMIT."
    )
    candidate_steps = [i for i, e in enumerate(events)
                       if e["kind"] == "STEP" and e["ptr"] in candidates]
    assert any(b < s < c for b in begin_positions for s in candidate_steps for c in commit_positions), (
        "The reused graph statement was not executed inside the immediate/exclusive transaction."
    )


def test_plan_txt_exists_and_matches_real_index():
    """Retain the original plan assertion and tie it to a real usable index."""
    assert os.path.exists(PLAN), f"Query plan file {PLAN} does not exist."
    with open(PLAN, "r", encoding="utf-8") as f:
        content = f.read()
    assert re.search(r"USING\s+INDEX|COVERING\s+INDEX", content, re.I), (
        "Query plan does not indicate index usage."
    )

    conn = sqlite3.connect(DB)
    try:
        names = []
        for row in conn.execute("PRAGMA index_list('user_connections')"):
            name = row[1]
            quoted = name.replace('"', '""')
            cols = [r[2] for r in conn.execute(f'PRAGMA index_info("{quoted}")')]
            if cols and cols[0] == "user_a":
                names.append(name)
        assert names
        assert any(re.search(r"\b" + re.escape(name) + r"\b", content) for name in names), (
            "plan.txt does not name any real suitable index on user_connections."
        )
    finally:
        conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
