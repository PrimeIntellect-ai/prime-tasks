#!/bin/bash
mkdir -p /logs/verifier

if (
    set -e

    cp /home/user/data.db /tmp/original_data.db
    trap 'cp /tmp/original_data.db /home/user/data.db; chmod 666 /home/user/data.db' EXIT

    cat << 'TRACE_EOF' > /tmp/sqlite_trace.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static int trace_callback(unsigned mask, void *ctx, void *p, void *x) {
    (void)ctx;
    (void)x;
    if (mask == SQLITE_TRACE_STMT) {
        const char *path = getenv("TRACE_LOG");
        const char *sql = sqlite3_sql((sqlite3_stmt *)p);
        if (path && sql) {
            FILE *f = fopen(path, "a");
            if (f) {
                fprintf(f, "%s\n", sql);
                fclose(f);
            }
        }
    }
    return 0;
}

typedef int (*open_fn)(const char *, sqlite3 **);
typedef int (*open_v2_fn)(const char *, sqlite3 **, int, const char *);

int sqlite3_open(const char *filename, sqlite3 **db) {
    static open_fn real_open = NULL;
    if (!real_open) real_open = (open_fn)dlsym(RTLD_NEXT, "sqlite3_open");
    int rc = real_open(filename, db);
    if (db && *db) sqlite3_trace_v2(*db, SQLITE_TRACE_STMT, trace_callback, NULL);
    return rc;
}

int sqlite3_open_v2(const char *filename, sqlite3 **db, int flags, const char *vfs) {
    static open_v2_fn real_open_v2 = NULL;
    if (!real_open_v2) real_open_v2 = (open_v2_fn)dlsym(RTLD_NEXT, "sqlite3_open_v2");
    int rc = real_open_v2(filename, db, flags, vfs);
    if (db && *db) sqlite3_trace_v2(*db, SQLITE_TRACE_STMT, trace_callback, NULL);
    return rc;
}
TRACE_EOF

    gcc -shared -fPIC /tmp/sqlite_trace.c -o /tmp/libsqlite_trace.so -ldl -lsqlite3

    test -e /home/user/find_pattern.cpp
    g++ -std=c++17 /home/user/find_pattern.cpp -o /tmp/find_pattern_submission -lsqlite3
    chmod 755 /tmp/find_pattern_submission

    rm -f /home/user/cycles.txt
    : > /tmp/sql_trace.log
    chmod 666 /tmp/sql_trace.log
    runuser -u user -- env TRACE_LOG=/tmp/sql_trace.log LD_PRELOAD=/tmp/libsqlite_trace.so timeout 20s /tmp/find_pattern_submission

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re

def test_cycles_output_exists():
    output_path = "/home/user/cycles.txt"
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"{output_path} is not a file."

def test_cycles_output_content():
    output_path = "/home/user/cycles.txt"
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."

    with open(output_path, "r") as f:
        content = f.read().strip().splitlines()

    expected_content = [
        "1,2,3",
        "10,11,12",
        "7,8,9"
    ]

    assert len(content) == len(expected_content), f"Expected {len(expected_content)} lines, but got {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_content)):
        assert actual.strip() == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual.strip()}'."

def test_cpp_source_exists():
    source_path = "/home/user/find_pattern.cpp"
    assert os.path.exists(source_path), f"C++ source file {source_path} does not exist."

def test_not_indexed_query_was_executed():
    with open("/tmp/sql_trace.log", "r") as f:
        statements = f.read()
    pattern = r"FROM\s+(?:[\"`\[])?communications(?:[\"`\]])?\s+NOT\s+INDEXED"
    assert re.search(pattern, statements, re.IGNORECASE), \
        "The executed SQLite statements did not query communications using NOT INDEXED."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
    cp /home/user/cycles.txt /tmp/initial_cycles.txt

    cat << 'DYNAMIC_EOF' > /tmp/create_dynamic_case.py
import json
import os
import secrets
import sqlite3

rng = secrets.SystemRandom()
labels = rng.sample(range(20, 900), 24)
edges = []

# Four valid directed triangles, with randomized orientation and chronology.
for i in range(4):
    triple = labels[i * 3:i * 3 + 3]
    rng.shuffle(triple)
    base = rng.randrange(1000, 9000)
    edges.extend([
        (triple[0], triple[1], base + 3),
        (triple[1], triple[2], base + 11),
        (triple[2], triple[0], base + 27),
    ])

# Two closed triangles for which no cyclic starting point has increasing times.
for i in range(4, 6):
    triple = labels[i * 3:i * 3 + 3]
    rng.shuffle(triple)
    base = rng.randrange(10000, 18000)
    edges.extend([
        (triple[0], triple[1], base + 20),
        (triple[1], triple[2], base + 10),
        (triple[2], triple[0], base + 30),
    ])

# Open-chain noise on otherwise unused nodes.
noise = labels[18:24]
edges.extend([
    (noise[0], noise[1], 41),
    (noise[1], noise[2], 42),
    (noise[3], noise[4], 43),
    (noise[4], noise[5], 44),
])
rng.shuffle(edges)

path = "/home/user/data.db"
if os.path.exists(path):
    os.unlink(path)
conn = sqlite3.connect(path)
conn.execute("CREATE TABLE communications(sender INT, receiver INT, time INT)")
conn.execute("CREATE INDEX idx_time ON communications(time)")
conn.executemany("INSERT INTO communications VALUES (?,?,?)", edges)
conn.commit()
conn.close()
os.chmod(path, 0o666)

cycles = set()
for s1, r1, t1 in edges:
    for s2, r2, t2 in edges:
        if r1 != s2 or not t1 < t2:
            continue
        for s3, r3, t3 in edges:
            if r2 == s3 and r3 == s1 and t2 < t3:
                seq = [s1, r1, r2]
                pos = seq.index(min(seq))
                seq = seq[pos:] + seq[:pos]
                cycles.add(",".join(map(str, seq)))

with open("/tmp/dynamic_expected.json", "w") as f:
    json.dump(sorted(cycles), f)
DYNAMIC_EOF

    python3 /tmp/create_dynamic_case.py
    rm -f /home/user/cycles.txt
    : > /tmp/sql_trace.log
    chmod 666 /tmp/sql_trace.log
    runuser -u user -- env TRACE_LOG=/tmp/sql_trace.log LD_PRELOAD=/tmp/libsqlite_trace.so timeout 20s /tmp/find_pattern_submission

    cat << 'VALIDATE_EOF' > /tmp/validate_dynamic.py
import json
import os
import re

output = "/home/user/cycles.txt"
assert os.path.exists(output), f"Output file {output} does not exist after dynamic run."
assert os.path.isfile(output), f"{output} is not a file."
with open(output) as f:
    actual = [line.strip() for line in f.read().strip().splitlines()]
with open("/tmp/dynamic_expected.json") as f:
    expected = json.load(f)
assert actual == expected, f"Dynamic case mismatch: expected {expected}, got {actual}"

with open("/tmp/sql_trace.log") as f:
    statements = f.read()
pattern = r"FROM\s+(?:[\"`\[])?communications(?:[\"`\]])?\s+NOT\s+INDEXED"
assert re.search(pattern, statements, re.IGNORECASE), \
    "The dynamic run did not query communications using NOT INDEXED."
VALIDATE_EOF

    python3 /tmp/validate_dynamic.py
    cp /tmp/initial_cycles.txt /home/user/cycles.txt
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
