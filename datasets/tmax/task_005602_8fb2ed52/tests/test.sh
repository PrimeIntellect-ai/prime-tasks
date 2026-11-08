#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import sqlite3
import subprocess
import uuid
import pytest

DB_PATH = "/home/user/legacy_etl.db"
BUILD_INDEXES_SCRIPT = "/home/user/build_indexes.sh"
GET_UPSTREAM_SCRIPT = "/home/user/get_upstream.sh"
SALES_LINEAGE_JSON = "/home/user/sales_lineage.json"


def test_build_indexes_script_exists():
    assert os.path.isfile(BUILD_INDEXES_SCRIPT), f"{BUILD_INDEXES_SCRIPT} does not exist."
    assert os.access(BUILD_INDEXES_SCRIPT, os.X_OK), f"{BUILD_INDEXES_SCRIPT} is not executable."


def test_build_indexes_script_execution():
    with open(BUILD_INDEXES_SCRIPT, "r") as f:
        script = f.read()
    assert re.search(r"\bsqlite3\b", script), "build_indexes.sh must use sqlite3."

    # Remove user-created indexes so the submitted script itself must recreate them.
    conn = sqlite3.connect(DB_PATH)
    indexes = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND sql IS NOT NULL"
    ).fetchall()
    for (name,) in indexes:
        quoted = name.replace('"', '""')
        conn.execute(f'DROP INDEX "{quoted}"')
    conn.commit()
    conn.close()

    result = subprocess.run(
        [BUILD_INDEXES_SCRIPT], cwd="/home/user", capture_output=True,
        text=True, timeout=15
    )
    assert result.returncode == 0, f"Index script failed: {result.stderr}"


def _index_leading_columns(conn, table):
    found = []
    for row in conn.execute(f"PRAGMA index_list('{table}')"):
        index_name = row[1]
        quoted = index_name.replace('"', '""')
        columns = [r[2] for r in conn.execute(f'PRAGMA index_info("{quoted}")')]
        if columns:
            found.append(columns)
    return found


def test_indexes_created():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT count(*) FROM sqlite_master WHERE type='index' AND tbl_name='job_deps';")
    index_count = cursor.fetchone()[0]
    assert index_count > 0, "No index was created on the 'job_deps' table."

    dep_indexes = _index_leading_columns(conn, "job_deps")
    job_indexes = _index_leading_columns(conn, "etl_jobs")
    conn.close()

    assert any(cols[0] == "downstream_id" for cols in dep_indexes), \
        "job_deps needs an index beginning with downstream_id for upstream traversal."
    assert any(cols[0] == "job_name" for cols in job_indexes), \
        "etl_jobs needs an index beginning with job_name for target lookup."


def test_get_upstream_script_exists():
    assert os.path.isfile(GET_UPSTREAM_SCRIPT), f"{GET_UPSTREAM_SCRIPT} does not exist."
    assert os.access(GET_UPSTREAM_SCRIPT, os.X_OK), f"{GET_UPSTREAM_SCRIPT} is not executable."

    with open(GET_UPSTREAM_SCRIPT, "r") as f:
        script = f.read()
    assert re.search(r"\bWITH\s+RECURSIVE\b", script, re.IGNORECASE), \
        "get_upstream.sh must query using a recursive CTE."
    assert re.search(r"\bsqlite3\b", script), "get_upstream.sh must use sqlite3."


def test_sales_lineage_json_correct():
    assert os.path.isfile(SALES_LINEAGE_JSON), f"{SALES_LINEAGE_JSON} does not exist."

    with open(SALES_LINEAGE_JSON, 'r') as f:
        saved_text = f.read()
        try:
            data = json.loads(saved_text)
        except json.JSONDecodeError:
            pytest.fail(f"{SALES_LINEAGE_JSON} does not contain valid JSON.")

    expected = [
        "Calculate_Metrics",
        "Clean_Marketing_Data",
        "Clean_Sales_Data",
        "Extract_Marketing_API",
        "Extract_Sales_DB",
        "Join_Sales_Marketing"
    ]

    assert isinstance(data, list), "Output JSON must be an array."
    assert sorted(data) == sorted(expected), f"Lineage data in {SALES_LINEAGE_JSON} does not match expected upstream jobs."
    assert data == expected, "sales_lineage.json must be alphabetically ordered."

    result = subprocess.run(
        [GET_UPSTREAM_SCRIPT, "Load_Fact_Sales"], capture_output=True,
        text=True, timeout=15
    )
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    assert saved_text == result.stdout, \
        "sales_lineage.json must contain exactly the script's standard output."


def test_get_upstream_script_execution():
    # Test the script with another job to ensure it works dynamically
    target_job = "Join_Sales_Marketing"
    expected_output = [
        "Clean_Marketing_Data",
        "Clean_Sales_Data",
        "Extract_Marketing_API",
        "Extract_Sales_DB"
    ]

    result = subprocess.run([GET_UPSTREAM_SCRIPT, target_job], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail("Script output is not valid JSON.")

    assert isinstance(data, list), "Script output must be a JSON array."
    assert sorted(data) == sorted(expected_output), f"Script output for {target_job} did not match expected upstream jobs."
    assert data == expected_output, "Script output must be sorted alphabetically."


def _derive_upstream(conn, target_name):
    row = conn.execute(
        "SELECT job_id FROM etl_jobs WHERE job_name = ?", (target_name,)
    ).fetchone()
    assert row is not None
    target_id = row[0]
    seen = set()
    stack = [target_id]
    while stack:
        downstream = stack.pop()
        for (upstream,) in conn.execute(
            "SELECT upstream_id FROM job_deps WHERE downstream_id = ?", (downstream,)
        ):
            if upstream not in seen and upstream != target_id:
                seen.add(upstream)
                stack.append(upstream)
    if not seen:
        return []
    placeholders = ",".join("?" for _ in seen)
    names = [r[0] for r in conn.execute(
        f"SELECT job_name FROM etl_jobs WHERE job_id IN ({placeholders})", tuple(seen)
    )]
    return sorted(names)


def test_get_upstream_on_runtime_generated_graph():
    # Runtime-only names prevent a fixed response for the image's original jobs.
    token = uuid.uuid4().hex
    names = [f"Runtime_{token}_{suffix}" for suffix in (
        "ZuluSource", "AlphaSource", "MiddleA", "MiddleB", "DeepNode",
        "MainTarget", "SmallTarget", "Independent"
    )]

    conn = sqlite3.connect(DB_PATH)
    start_id = conn.execute("SELECT COALESCE(MAX(job_id), 0) + 1 FROM etl_jobs").fetchone()[0]
    ids = {name: start_id + i for i, name in enumerate(names)}
    conn.executemany(
        "INSERT INTO etl_jobs(job_id, job_name) VALUES (?, ?)",
        [(ids[name], name) for name in names]
    )
    edges = [
        (ids[names[0]], ids[names[2]]),
        (ids[names[1]], ids[names[2]]),
        (ids[names[1]], ids[names[3]]),
        (ids[names[2]], ids[names[4]]),
        (ids[names[3]], ids[names[4]]),
        (ids[names[4]], ids[names[5]]),
        (ids[names[0]], ids[names[6]]),
    ]
    conn.executemany(
        "INSERT INTO job_deps(upstream_id, downstream_id) VALUES (?, ?)", edges
    )
    conn.commit()

    targets = [names[5], names[6], names[7], names[4], names[2]]
    expected = {target: _derive_upstream(conn, target) for target in targets}
    conn.close()

    for target in targets:
        result = subprocess.run(
            [GET_UPSTREAM_SCRIPT, target], capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, f"Script failed for {target}: {result.stderr}"
        try:
            data = json.loads(result.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Script output for {target} is not valid JSON: {result.stdout!r}")
        assert isinstance(data, list), "Script output must be a JSON array."
        assert all(isinstance(item, str) for item in data), \
            "Every JSON array element must be a string."
        assert data == expected[target], \
            f"Incorrect or non-alphabetical recursive lineage for {target}."
        assert target not in data, "The target job must not appear in its own lineage."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
