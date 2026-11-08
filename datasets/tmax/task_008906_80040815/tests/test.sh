#!/bin/bash
set -e
mkdir -p /logs/verifier

run_checks() {
    cd /home/user/project

    # Require the submitted Go package to genuinely use cgo and the evaluator API.
    cgo_files="$(go list -f '{{.CgoFiles}}' .)"
    [ "$cgo_files" != "[]" ]

    python3 - <<'PY'
import re
from pathlib import Path
src = Path('/home/user/project/main.go').read_text()
# Remove comments before checking that these are executable source constructs.
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
src = re.sub(r'//[^\n]*', '', src)
assert re.search(r'C\s*\.\s*evaluate_expression', src), 'main.go does not call the C evaluator'
assert re.search(r'wg\s*\.\s*Add\s*\(', src), 'worker WaitGroup is never incremented'
assert re.search(r'wg\s*\.\s*Done\s*\(', src), 'workers do not signal completion'
assert re.search(r'(range\s+jobs|<-\s*jobs)', src), 'workers do not receive from jobs'
PY

    test -f /home/user/project/evaluator.h

    # Compile and exercise the C-linkage API independently, including both logical operators.
    cat > /tmp/evaluator_test.cpp <<'CPP'
#include "/home/user/project/evaluator.h"
#include <cstdlib>
int main() {
    if (evaluate_expression("ext == \".txt\" AND size < 100", ".txt", 50) != 1) return 1;
    if (evaluate_expression("ext == \".txt\" AND size < 100", ".txt", 150) != 0) return 2;
    if (evaluate_expression("ext == \".txt\" AND size < 100", ".cpp", 50) != 0) return 3;
    if (evaluate_expression("ext == \".txt\" OR size < 100", ".txt", 150) != 1) return 4;
    if (evaluate_expression("ext == \".txt\" OR size < 100", ".cpp", 50) != 1) return 5;
    if (evaluate_expression("ext == \".txt\" OR size < 100", ".cpp", 150) != 0) return 6;
    return 0;
}
CPP
    g++ -std=c++17 /tmp/evaluator_test.cpp /home/user/project/evaluator.cpp -o /tmp/evaluator_test
    /tmp/evaluator_test

    # Build the submitted Go/C++ program from source.
    CGO_ENABLED=1 go build -o /tmp/project_under_test .

    seed_database() {
        rm -f /home/user/project/files.db /home/user/project/matched_files.log
        python3 - <<'PY'
import sqlite3
p = '/home/user/project/files.db'
conn = sqlite3.connect(p)
conn.execute('CREATE TABLE files_v1 (id INTEGER PRIMARY KEY, path TEXT)')
conn.commit()
conn.close()
PY
    }

    # Exercise OR through the built Go/cgo program on additional inputs.
    head -c 150 /dev/zero > /home/user/project/data/verifier_false.bin
    head -c 20 /dev/zero > /home/user/project/data/verifier_small.bin
    head -c 300 /dev/zero > /home/user/project/data/verifier_text.txt
    seed_database
    timeout 60 /tmp/project_under_test 'ext == ".txt" OR size < 100'

    python3 - <<'PY'
import os
import sqlite3
expr = 'ext == ".txt" OR size < 100'
data = '/home/user/project/data'
expected = sorted(
    os.path.join(data, name)
    for name in os.listdir(data)
    if os.path.isfile(os.path.join(data, name))
    and (os.path.splitext(name)[1] == '.txt' or os.path.getsize(os.path.join(data, name)) < 100)
)
with open('/home/user/project/matched_files.log') as f:
    actual = [line.strip() for line in f if line.strip()]
assert actual == expected, (actual, expected)
conn = sqlite3.connect('/home/user/project/files.db')
assert conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='files_v1'").fetchone() is None
rows = conn.execute('SELECT path, matched_rule FROM files_v2 ORDER BY path').fetchall()
conn.close()
assert rows == [(path, expr) for path in expected], rows
PY

    rm -f /home/user/project/data/verifier_false.bin \
          /home/user/project/data/verifier_small.bin \
          /home/user/project/data/verifier_text.txt

    # Re-run the required command from a legacy v1 database so the final-state
    # assertions also verify the requested migration and fixed output.
    seed_database
    timeout 60 /tmp/project_under_test 'ext == ".txt" AND size < 100'

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import pytest

LOG_PATH = "/home/user/project/matched_files.log"
DB_PATH = "/home/user/project/files.db"
RULE = 'ext == ".txt" AND size < 100'

EXPECTED_PATHS = [
    "/home/user/project/data/a.txt",
    "/home/user/project/data/d.txt"
]

def test_matched_files_log():
    assert os.path.isfile(LOG_PATH), f"Expected log file does not exist: {LOG_PATH}"
    with open(LOG_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert lines == EXPECTED_PATHS, f"Contents of {LOG_PATH} do not match the expected sorted paths. Got: {lines}"

def test_database_exists():
    assert os.path.isfile(DB_PATH), f"Expected database file does not exist: {DB_PATH}"

def test_database_schema():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='files_v2';")
    table = cursor.fetchone()
    assert table is not None, "Table 'files_v2' does not exist in the database."
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='files_v1';")
    assert cursor.fetchone() is None, "Legacy table 'files_v1' was not migrated."
    cursor.execute("PRAGMA table_info(files_v2);")
    columns = {row[1] for row in cursor.fetchall()}
    expected_columns = {"id", "path", "matched_rule"}
    assert expected_columns.issubset(columns), f"Table 'files_v2' is missing required columns. Expected at least {expected_columns}, got {columns}"
    conn.close()

def test_database_content():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT path, matched_rule FROM files_v2 ORDER BY path;")
        rows = cursor.fetchall()
    except sqlite3.OperationalError as e:
        pytest.fail(f"Failed to query files_v2 table: {e}")
    finally:
        conn.close()
    assert [row[0] for row in rows] == EXPECTED_PATHS, f"Database paths do not match expected paths. Got: {[row[0] for row in rows]}"
    assert [row[1] for row in rows] == [RULE] * len(EXPECTED_PATHS), f"Database matched_rule values are incorrect: {rows}"
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
}

if run_checks 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
