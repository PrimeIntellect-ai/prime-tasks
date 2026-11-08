#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import subprocess
import pytest

DB_PATH = "/home/user/graph.db"
QUERY_PATH = "/home/user/query.sql"
SCRIPT_PATH = "/home/user/verify_plan.sh"

EXPECTED_QUERY = """WITH RECURSIVE impact AS (
    SELECT target_id FROM relations WHERE source_id = 42
    UNION
    SELECT r.target_id FROM relations r
    INNER JOIN impact i ON r.source_id = i.target_id
)
SELECT e.name FROM entities e
JOIN impact i ON e.id = i.target_id
WHERE e.type = 'Application';
"""

EXPECTED_IMPACT = [
    "App-Backend-API",
    "App-Frontend-Web",
    "App-Reporting",
]


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def explain_details(query, automatic_indexes=True):
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("PRAGMA automatic_index = %s" % ("ON" if automatic_indexes else "OFF"))
        return [row[3] for row in conn.execute("EXPLAIN QUERY PLAN " + query).fetchall()]
    except sqlite3.Error as e:
        pytest.fail(f"Failed to execute EXPLAIN QUERY PLAN: {e}")
    finally:
        conn.close()


def assert_plan_appears_in_output(details, output):
    normalized_output = " ".join(output.upper().split())
    for detail in details:
        normalized_detail = " ".join(detail.upper().split())
        assert normalized_detail in normalized_output, (
            f"verify_plan.sh output is missing the real plan detail: {detail!r}"
        )


def test_impact_txt_content():
    impact_path = "/home/user/impact.txt"
    assert os.path.exists(impact_path), f"File {impact_path} does not exist."
    lines = read_nonempty_lines(impact_path)
    assert lines == EXPECTED_IMPACT, (
        f"Contents of {impact_path} do not match the expected sorted output."
    )

    with open(QUERY_PATH, "r") as f:
        query = f.read()
    conn = sqlite3.connect(DB_PATH)
    try:
        actual = sorted(row[0] for row in conn.execute(query).fetchall())
    except sqlite3.Error as e:
        pytest.fail(f"Failed to execute the supplied query: {e}")
    finally:
        conn.close()
    assert lines == actual, "impact.txt is not the sorted raw output of query.sql."


def test_query_sql_unmodified():
    assert os.path.exists(QUERY_PATH), f"File {QUERY_PATH} does not exist."
    with open(QUERY_PATH, "r") as f:
        content = f.read()
    assert content.strip() == EXPECTED_QUERY.strip(), f"File {QUERY_PATH} was modified."


def test_database_indexes():
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} does not exist."
    with open(QUERY_PATH, "r") as f:
        query = f.read()

    # Automatic transient indexes must not satisfy the indexing requirement.
    plan = explain_details(query, automatic_indexes=False)

    forbidden_scan = re.compile(
        r"\bSCAN\s+(?:TABLE\s+)?(?:ENTITIES|RELATIONS|E|R)\b", re.IGNORECASE
    )
    for detail in plan:
        if forbidden_scan.search(detail):
            pytest.fail(f"Query plan still contains a full scan of a main table: {detail}")

    search_targets = []
    for detail in plan:
        match = re.search(r"\bSEARCH\s+(?:TABLE\s+)?([A-Za-z_][A-Za-z0-9_]*)\b", detail, re.IGNORECASE)
        if match:
            search_targets.append(match.group(1).lower())

    assert "relations" in search_targets, (
        f"The anchor access to relations is not an indexed SEARCH: {plan}"
    )
    assert "r" in search_targets, (
        f"The recursive access to relations is not an indexed SEARCH: {plan}"
    )
    assert "e" in search_targets or "entities" in search_targets, (
        f"The entities access is not an indexed SEARCH: {plan}"
    )

    conn = sqlite3.connect(DB_PATH)
    try:
        user_indexes = conn.execute(
            "SELECT name FROM sqlite_master "
            "WHERE type='index' AND sql IS NOT NULL"
        ).fetchall()
    finally:
        conn.close()
    assert user_indexes, "No persistent user-created indexes were added to graph.db."


def test_verify_plan_sh():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    with open(QUERY_PATH, "r") as f:
        original_query = f.read()

    main_details = explain_details(original_query)
    main_result = subprocess.run(
        [SCRIPT_PATH], capture_output=True, text=True, cwd="/home/user", timeout=20
    )
    assert main_result.returncode == 0, f"Script {SCRIPT_PATH} failed to execute."
    output = main_result.stdout.upper()
    assert "QUERY PLAN" in output or "SEARCH TABLE" in output or "SCAN TABLE" in output or "SEARCH " in output or "SCAN " in output, \
        f"Script {SCRIPT_PATH} does not seem to output a query plan."
    assert_plan_appears_in_output(main_details, main_result.stdout)

    # Verify that the script actually reads and explains query.sql rather than
    # printing a fixed plan or merely printing the words 'QUERY PLAN'.
    probe_query = "SELECT name FROM entities WHERE id = 42424242 AND type = 'Application';\n"
    try:
        with open(QUERY_PATH, "w") as f:
            f.write(probe_query)
        probe_details = explain_details(probe_query)
        probe_result = subprocess.run(
            [SCRIPT_PATH], capture_output=True, text=True, cwd="/home/user", timeout=20
        )
    finally:
        with open(QUERY_PATH, "w") as f:
            f.write(original_query)

    assert probe_result.returncode == 0, (
        f"Script {SCRIPT_PATH} failed while explaining query.sql."
    )
    assert probe_result.stdout != main_result.stdout, (
        "verify_plan.sh appears to print fixed output instead of explaining query.sql."
    )
    assert_plan_appears_in_output(probe_details, probe_result.stdout)

    with open(QUERY_PATH, "r") as f:
        assert f.read().strip() == EXPECTED_QUERY.strip(), "query.sql was not restored after verification."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
