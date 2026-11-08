#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import sqlite3
import string
import subprocess
import sys

import pytest


def test_recovered_db_exists_and_valid():
    recovered_path = "/home/user/data/recovered.db"
    assert os.path.exists(recovered_path), f"Recovered database not found at {recovered_path}"

    try:
        conn = sqlite3.connect(recovered_path)
        c = conn.cursor()
        c.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = [row[0] for row in c.fetchall()]
        assert "records" in tables, f"Expected 'records' table in recovered DB, found: {tables}"

        integrity = c.execute("PRAGMA integrity_check").fetchone()
        assert integrity == ("ok",), f"Recovered database failed integrity check: {integrity}"

        columns = c.execute("PRAGMA table_info(records)").fetchall()
        column_names = [row[1] for row in columns]
        assert column_names == ["id", "payload"], f"Unexpected records schema: {column_names}"

        rows = c.execute("SELECT id, payload FROM records ORDER BY id").fetchall()
        assert rows == [(1, "323f363635"), (2, "123")], \
            f"Recovered records do not match the contents of events.db: {rows}"
        conn.close()
    except sqlite3.DatabaseError as e:
        pytest.fail(f"Recovered database is invalid or corrupted: {e}")


def generate_eval_db(db_path, num_rows=100000):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("CREATE TABLE records (id INTEGER PRIMARY KEY, payload TEXT)")

    rows = []
    for i in range(num_rows):
        if random.random() < 0.8:
            text = ''.join(random.choices(string.ascii_letters + string.digits, k=20))
            payload = bytes([b ^ 0x5A for b in text.encode('utf-8')]).hex()
        else:
            if random.random() < 0.5:
                payload = "12345"
            else:
                payload = "ZZZZ"
        rows.append((i, payload))

    c.executemany("INSERT INTO records (id, payload) VALUES (?, ?)", rows)
    conn.commit()
    conn.close()


def golden_processor(db_path):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT id, payload FROM records")
    results = {}
    for row_id, payload in c:
        try:
            if len(payload) % 2 != 0:
                continue
            bytes_data = bytes.fromhex(payload)
            transformed = bytes([b ^ 0x5A for b in bytes_data]).decode('utf-8')
            results[str(row_id)] = transformed
        except Exception:
            continue
    conn.close()
    return results


def test_assertion_based_validation():
    script_path = "/home/user/safe_processor.py"
    assert os.path.exists(script_path), f"Expected script not found at {script_path}"

    with open(script_path, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=script_path)
    assertions = [node for node in ast.walk(tree) if isinstance(node, ast.Assert)]
    assert assertions, "safe_processor.py must use assert statements for payload validation"
    assert any(not isinstance(node.test, ast.Constant) for node in assertions), \
        "Payload validation assertion must test a non-constant condition"

    db_path = "/tmp/assert_eval.db"
    out_path = "/tmp/assert_out.json"
    marker_path = "/tmp/assert_seen.txt"
    for path in (db_path, out_path, marker_path):
        if os.path.exists(path):
            os.remove(path)

    conn = sqlite3.connect(db_path)
    conn.execute("CREATE TABLE records (id INTEGER PRIMARY KEY, payload TEXT)")
    conn.executemany(
        "INSERT INTO records (id, payload) VALUES (?, ?)",
        [(1, "323f363635"), (2, "123"), (3, "ZZZZ")],
    )
    conn.commit()
    conn.close()

    wrapper = r'''
import os
import runpy
import sys

script, db_path, out_path, marker_path = sys.argv[1:]
script = os.path.realpath(script)
seen = 0

def trace(frame, event, arg):
    global seen
    if (event == "exception" and
            os.path.realpath(frame.f_code.co_filename) == script and
            arg[0] is AssertionError):
        seen += 1
    return trace

sys.settrace(trace)
sys.argv = [script, db_path, out_path]
try:
    runpy.run_path(script, run_name="__main__")
except SystemExit as exc:
    if exc.code not in (None, 0):
        raise
finally:
    sys.settrace(None)
    with open(marker_path, "w") as marker:
        marker.write(str(seen))
'''
    result = subprocess.run(
        [sys.executable, "-c", wrapper, script_path, db_path, out_path, marker_path],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Script failed during validation test:\n{result.stderr}"
    assert os.path.exists(marker_path), "Could not observe assertion-based validation"
    with open(marker_path, "r") as f:
        assertion_count = int(f.read())
    assert assertion_count > 0, "Malformed payloads did not trigger assertion-based validation"

    assert os.path.exists(out_path), "Validation test output JSON was not created"
    with open(out_path, "r") as f:
        results = json.load(f)
    assert results == {"1": "hello"}, f"Malformed payloads were not correctly dropped: {results}"


def test_safe_processor_accuracy_and_memory():
    script_path = "/home/user/safe_processor.py"
    assert os.path.exists(script_path), f"Expected script not found at {script_path}"

    eval_db_path = "/tmp/eval.db"
    out_json_path = "/tmp/out.json"
    if os.path.exists(eval_db_path):
        os.remove(eval_db_path)
    if os.path.exists(out_json_path):
        os.remove(out_json_path)

    generate_eval_db(eval_db_path, num_rows=100000)

    cmd = ["/usr/bin/time", "-v", sys.executable, script_path, eval_db_path, out_json_path]
    result = subprocess.run(cmd, capture_output=True, text=True)

    assert result.returncode == 0, f"Script failed with error:\n{result.stderr}"

    max_memory_kb = None
    for line in result.stderr.splitlines():
        if "Maximum resident set size (kbytes):" in line:
            max_memory_kb = int(line.split(":")[1].strip())
            break

    assert max_memory_kb is not None, "Could not parse memory usage from /usr/bin/time output"
    max_memory_mb = max_memory_kb / 1024.0
    assert max_memory_mb <= 50.0, f"Memory limit exceeded: {max_memory_mb:.2f} MB > 50.0 MB"

    assert os.path.exists(out_json_path), "Output JSON file was not created"
    with open(out_json_path, 'r') as f:
        try:
            agent_results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Output JSON is invalid")

    golden_results = golden_processor(eval_db_path)
    assert len(agent_results) == len(golden_results), \
        f"Result count mismatch. Expected {len(golden_results)}, got {len(agent_results)}"

    for k, v in golden_results.items():
        assert k in agent_results, f"Missing key {k} in output"
        assert agent_results[k] == v, f"Value mismatch for key {k}. Expected {v}, got {agent_results[k]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
