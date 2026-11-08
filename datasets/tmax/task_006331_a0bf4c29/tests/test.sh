#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
import subprocess
import pytest

DB_PATH = "/home/user/telemetry.db"
C_FILE_PATH = "/home/user/etl_extract.c"
EXEC_PATH = "/home/user/etl_extract"
JSON_OUT_PATH = "/home/user/extract.json"
BIND_LOG = "/tmp/sqlite_bind.log"
PRELOAD_PATH = "/tmp/bind_trace.so"


def expected_rows(status, limit, offset):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    rows = conn.execute('''
        SELECT id, sensor_id, timestamp, reading
        FROM sensor_data
        WHERE status = ?
        ORDER BY timestamp DESC
        LIMIT ? OFFSET ?
    ''', (status, limit, offset)).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def compile_program_and_tracer():
    result = subprocess.run(
        ["gcc", "-Wall", "-Wextra", C_FILE_PATH, "-o", EXEC_PATH, "-lsqlite3"],
        text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, f"C program failed to compile:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(EXEC_PATH), f"Executable {EXEC_PATH} was not created."
    assert os.access(EXEC_PATH, os.X_OK), f"{EXEC_PATH} is not executable."
    with open(EXEC_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXEC_PATH} is not an ELF executable."

    tracer_source = r'''
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static void record_bind(int index) {
    const char *path = getenv("SQLITE_BIND_LOG");
    if (!path) return;
    FILE *f = fopen(path, "a");
    if (f) { fprintf(f, "%d\n", index); fclose(f); }
}

int sqlite3_bind_text(sqlite3_stmt *s, int i, const char *v, int n, void(*d)(void*)) {
    static int (*real_fn)(sqlite3_stmt*,int,const char*,int,void(*)(void*)) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_text");
    record_bind(i);
    return real_fn(s, i, v, n, d);
}

int sqlite3_bind_int(sqlite3_stmt *s, int i, int v) {
    static int (*real_fn)(sqlite3_stmt*,int,int) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_int");
    record_bind(i);
    return real_fn(s, i, v);
}

int sqlite3_bind_int64(sqlite3_stmt *s, int i, sqlite3_int64 v) {
    static int (*real_fn)(sqlite3_stmt*,int,sqlite3_int64) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_int64");
    record_bind(i);
    return real_fn(s, i, v);
}
'''
    with open("/tmp/bind_trace.c", "w", encoding="utf-8") as f:
        f.write(tracer_source)
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", "/tmp/bind_trace.c", "-o", PRELOAD_PATH, "-ldl"],
        text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, f"Failed to build binding tracer:\n{result.stdout}\n{result.stderr}"


@pytest.fixture(scope="session", autouse=True)
def compiled_artifacts():
    assert os.path.exists(C_FILE_PATH), f"C source file {C_FILE_PATH} is missing."
    compile_program_and_tracer()


def run_extractor(status, limit, offset):
    expected = expected_rows(status, limit, offset)
    if os.path.exists(BIND_LOG):
        os.unlink(BIND_LOG)
    if os.path.exists(JSON_OUT_PATH):
        os.unlink(JSON_OUT_PATH)

    env = os.environ.copy()
    env["LD_PRELOAD"] = PRELOAD_PATH
    env["SQLITE_BIND_LOG"] = BIND_LOG
    result = subprocess.run(
        [EXEC_PATH, status, str(limit), str(offset)],
        text=True, capture_output=True, env=env, timeout=15
    )
    assert result.returncode == 0, (
        f"Extractor failed for arguments {status!r}, {limit}, {offset}:\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.exists(JSON_OUT_PATH), f"Output file {JSON_OUT_PATH} was not created."
    try:
        with open(JSON_OUT_PATH, "r", encoding="utf-8") as f:
            actual = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse {JSON_OUT_PATH} as JSON: {e}")

    assert isinstance(actual, list), "The JSON output should be a list of objects."
    assert actual == expected, f"Expected {expected}, but extractor produced {actual}."
    assert os.path.exists(BIND_LOG), "No sqlite3_bind_* calls were observed while running the extractor."
    with open(BIND_LOG, "r", encoding="utf-8") as f:
        bound_indexes = {int(line.strip()) for line in f if line.strip()}
    assert {1, 2, 3}.issubset(bound_indexes), (
        "The running extractor must bind the status, limit, and offset parameters; "
        f"observed parameter indexes were {sorted(bound_indexes)}."
    )


def test_index_created():
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_status_time';")
    row = cursor.fetchone()
    assert row is not None, "Index 'idx_status_time' does not exist in the database."

    index_rows = cursor.execute("PRAGMA index_xinfo('idx_status_time')").fetchall()
    conn.close()
    key_columns = [(r[2], r[3]) for r in index_rows if r[5] == 1]
    assert key_columns == [("status", 0), ("timestamp", 1)], (
        "Index 'idx_status_time' must index exactly status followed by timestamp DESC; "
        f"found {key_columns}."
    )


def test_c_program_uses_bindings():
    assert os.path.exists(C_FILE_PATH), f"C source file {C_FILE_PATH} is missing."
    with open(C_FILE_PATH, 'r', encoding='utf-8') as f:
        content = f.read()

    bind_count = content.count("sqlite3_bind_")
    assert bind_count >= 3, (
        f"Expected at least 3 sqlite3_bind_* calls in {C_FILE_PATH} to prevent SQL injection, "
        f"but found {bind_count}."
    )


def test_exact_argument_count():
    for args in ([], ["ERROR", "5", "10", "extra"]):
        result = subprocess.run([EXEC_PATH] + args, text=True, capture_output=True, timeout=10)
        assert result.returncode != 0, "Extractor must reject calls that do not provide exactly three arguments."


def test_extractor_on_derived_inputs_and_injection():
    conn = sqlite3.connect(DB_PATH)
    statuses = [r[0] for r in conn.execute("SELECT DISTINCT status FROM sensor_data ORDER BY status").fetchall()]
    conn.close()
    assert statuses
    run_extractor(statuses[0], 3, 2)
    if len(statuses) > 1:
        run_extractor(statuses[-1], 7, 1)
    run_extractor("ERROR' OR 1=1 --", 4, 0)


def test_json_output_correct():
    run_extractor("ERROR", 5, 10)

    with open(JSON_OUT_PATH, 'r', encoding='utf-8') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {JSON_OUT_PATH} as JSON: {e}")

    assert isinstance(actual_data, list), "The JSON output should be a list of objects."

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('''
        SELECT id, sensor_id, timestamp, reading
        FROM sensor_data
        WHERE status = ?
        ORDER BY timestamp DESC
        LIMIT ? OFFSET ?
    ''', ("ERROR", 5, 10))
    expected_data = [{
        "id": r["id"],
        "sensor_id": r["sensor_id"],
        "timestamp": r["timestamp"],
        "reading": r["reading"]
    } for r in cursor.fetchall()]
    conn.close()

    assert actual_data == expected_data, (
        f"JSON data in {JSON_OUT_PATH} does not match expected output.\n"
        f"Expected: {expected_data}\nActual: {actual_data}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
