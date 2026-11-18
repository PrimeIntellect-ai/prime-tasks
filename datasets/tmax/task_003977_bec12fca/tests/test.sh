#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
import time
import pytest

SCRIPT_PATH = "/home/user/run_audit.sh"
DB_PATH = "/app/audit.db"


def test_run_audit_sh_exists():
    assert os.path.isfile(SCRIPT_PATH), "/home/user/run_audit.sh does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK) or os.access(SCRIPT_PATH, os.R_OK), "/home/user/run_audit.sh is not readable/executable."

    source = open(SCRIPT_PATH, "r", encoding="utf-8", errors="replace").read()
    # Remove ordinary shell/SQL comments before checking the required SQL constructs.
    uncommented = re.sub(r"(?m)^\s*#.*$", "", source)
    uncommented = re.sub(r"(?m)--.*$", "", uncommented)
    uncommented = re.sub(r"/\*.*?\*/", "", uncommented, flags=re.S)
    assert re.search(r"\bWITH\s+RECURSIVE\b", uncommented, re.I), "The script must use a Recursive CTE."
    assert re.search(r"\bSUM\s*\([^)]*\)\s*OVER\s*\(", uncommented, re.I | re.S), "The script must use a SUM window function for cumulative duration."
    assert re.search(r"duration_seconds", uncommented, re.I), "The query must use duration_seconds."


def run_and_validate(user_id, expected_chain, expected_duration, expected_path_length):
    start = time.perf_counter()
    result = subprocess.run(
        ["bash", SCRIPT_PATH, str(user_id)],
        capture_output=True,
        text=True,
        timeout=5,
    )
    execution_time = time.perf_counter() - start

    assert result.returncode == 0, f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
    try:
        output_data = json.loads(result.stdout.strip())
    except json.JSONDecodeError:
        pytest.fail(f"Script output is not valid JSON. Output: {result.stdout}")

    assert isinstance(output_data, list), "Output JSON must be a list."
    assert len(output_data) == 1, "Output JSON must contain exactly one result object."
    first_item = output_data[0]
    assert isinstance(first_item, dict), "The result must be a JSON object."
    assert set(first_item) == {"path_length", "total_duration", "system_chain"}, "Output object does not have the exact required schema."
    assert type(first_item["path_length"]) is int, "path_length must be an integer."
    assert type(first_item["total_duration"]) is int, "total_duration must be an integer."
    assert isinstance(first_item["system_chain"], list), "system_chain must be a list of hostnames."
    assert all(isinstance(x, str) for x in first_item["system_chain"]), "Every system_chain element must be a hostname string."
    assert len(first_item["system_chain"]) > 0, "system_chain list is empty."
    assert first_item["system_chain"][0] == "entry.corp.local", "The system chain must start with entry.corp.local."

    assert first_item["path_length"] == expected_path_length, f"Expected path length {expected_path_length}, got {first_item['path_length']}."
    assert first_item["total_duration"] == expected_duration, f"Expected total duration {expected_duration}, got {first_item['total_duration']}."
    assert first_item["system_chain"] == expected_chain, f"Incorrect system chain: {first_item['system_chain']}"
    assert execution_time < 0.5, f"Execution time {execution_time:.3f}s exceeded the 0.5s threshold."


def derive_linear_expected(conn, user_id):
    current = 1
    visited = {current}
    chain_ids = [current]
    total = 0
    while True:
        rows = conn.execute(
            "SELECT dest_sys_id, duration_seconds FROM access_logs WHERE user_id=? AND source_sys_id=? ORDER BY log_id",
            (user_id, current),
        ).fetchall()
        assert len(rows) <= 1, "Verifier fixture is not a linear path."
        if not rows:
            break
        dest, duration = rows[0]
        assert dest not in visited, "Verifier fixture unexpectedly contains a cycle."
        visited.add(dest)
        chain_ids.append(dest)
        total += duration
        current = dest
    hostnames = [conn.execute("SELECT hostname FROM systems WHERE sys_id=?", (sid,)).fetchone()[0] for sid in chain_ids]
    return hostnames, total, len(chain_ids) - 1


def test_script_execution_and_output():
    # Preserve the original target-user assertions, now including the complete chain and duration.
    run_and_validate(
        8041,
        ["entry.corp.local", "sys2.corp.local", "sys3.corp.local", "sys4.corp.local", "sys5.corp.local"],
        70,
        4,
    )

    # Add isolated, verifier-created users so output must depend on the supplied argument and database rows.
    fixtures = {
        987654321: [(1, 9001, 7), (9001, 9002, 11), (9002, 9003, 13)],
        987654322: [(1, 9010, 17)],
    }
    conn = sqlite3.connect(DB_PATH)
    try:
        for uid, edges in fixtures.items():
            conn.execute("DELETE FROM access_logs WHERE user_id=?", (uid,))
            conn.executemany(
                "INSERT INTO access_logs(source_sys_id,dest_sys_id,user_id,timestamp,duration_seconds) VALUES(?,?,?,?,?)",
                [(src, dst, uid, "2099-01-01 00:00:00", duration) for src, dst, duration in edges],
            )
        conn.commit()

        expected = {uid: derive_linear_expected(conn, uid) for uid in fixtures}
        for uid in fixtures:
            chain, duration, path_length = expected[uid]
            run_and_validate(uid, chain, duration, path_length)
    finally:
        for uid in fixtures:
            conn.execute("DELETE FROM access_logs WHERE user_id=?", (uid,))
        conn.commit()
        conn.close()


def test_z_database_has_and_uses_traversal_index():
    conn = sqlite3.connect(DB_PATH)
    try:
        suitable = []
        for row in conn.execute("PRAGMA index_list('access_logs')"):
            index_name = row[1]
            is_partial = bool(row[4]) if len(row) > 4 else False
            columns = [r[2] for r in conn.execute(f"PRAGMA index_info('{index_name}')")]
            if not is_partial and len(columns) >= 2 and set(columns[:2]) == {"user_id", "source_sys_id"}:
                suitable.append(index_name)
        assert suitable, "A persistent composite index on access_logs(user_id, source_sys_id), in either order, is required."

        plan = conn.execute(
            "EXPLAIN QUERY PLAN SELECT dest_sys_id, duration_seconds FROM access_logs WHERE user_id=? AND source_sys_id=?",
            (8041, 1),
        ).fetchall()
        plan_text = " ".join(str(row[3]) for row in plan).upper()
        assert "SEARCH ACCESS_LOGS USING INDEX" in plan_text, f"Traversal lookup is not using an index: {plan_text}"
    finally:
        conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
