#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import sqlite3
import stat
import subprocess

import pytest

SCRIPT_PATH = "/home/user/validate_backup.sh"
DB_PATH = "/home/user/backup_meta.db"
PATHS_LOG = "/home/user/paths.log"
PLAN_LOG = "/home/user/plan.log"
MONGO_PIPELINE = "/home/user/mongo_pipeline.json"
OUTPUTS = [PATHS_LOG, PLAN_LOG, MONGO_PIPELINE]


def token(prefix):
    return prefix + secrets.token_hex(6)


TENANT_A = 100000 + secrets.randbelow(800000)
TENANT_B = 100000 + secrets.randbelow(800000)
while TENANT_B == TENANT_A or TENANT_B in (455, 999):
    TENANT_B = 100000 + secrets.randbelow(800000)

A_ROOT = token("a_root_")
A_DIR = token("a_dir_")
A_FILE = token("a_file_")
A_SECOND_ROOT = token("a_second_")
A_SECOND_FILE = token("a_leaf_")
B_ROOT = token("b_root_")
B_DIR = token("b_dir_")
B_FILE = token("b_file_")
CROSS_A = token("cross_a_")
CROSS_B = token("cross_b_")

ROWS = [
    (1, None, "backup_root", 455),
    (2, 1, "etc", 455),
    (3, 1, "var", 455),
    (4, 2, "passwd", 455),
    (5, 3, "log", 455),
    (6, 5, "syslog", 455),
    (7, None, "backup_root_999", 999),
    (8, 7, "bin", 999),
    (100, None, A_ROOT, TENANT_A),
    (101, 100, A_DIR, TENANT_A),
    (102, 101, A_FILE, TENANT_A),
    (103, None, A_SECOND_ROOT, TENANT_A),
    (104, 103, A_SECOND_FILE, TENANT_A),
    (200, None, B_ROOT, TENANT_B),
    (201, 200, B_DIR, TENANT_B),
    (202, 201, B_FILE, TENANT_B),
    # These cross-tenant links catch recursive terms that fail to retain
    # the tenant predicate.
    (300, 100, CROSS_B, TENANT_B),
    (301, 200, CROSS_A, TENANT_A),
]


def expected_paths(tenant_id):
    own = {row[0]: row for row in ROWS if row[3] == tenant_id}
    children = {}
    for row in own.values():
        children.setdefault(row[1], []).append(row)

    result = []

    def visit(row, path):
        result.append(path)
        for child in children.get(row[0], []):
            visit(child, path + "/" + child[2])

    for root in children.get(None, []):
        visit(root, root[2])
    return sorted(result)


def create_database(index_name):
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    con = sqlite3.connect(DB_PATH)
    try:
        con.execute(
            "CREATE TABLE filesystem ("
            "id INTEGER PRIMARY KEY, parent_id INTEGER, name TEXT, "
            "tenant_id INTEGER)"
        )
        con.executemany(
            "INSERT INTO filesystem (id, parent_id, name, tenant_id) "
            "VALUES (?, ?, ?, ?)",
            ROWS,
        )
        con.execute(
            'CREATE INDEX "{}" ON filesystem(tenant_id, parent_id)'.format(index_name)
        )
        con.commit()
    finally:
        con.close()
    os.chmod(DB_PATH, 0o666)


def validate_pipeline(tenant_id, backup_date):
    assert os.path.isfile(MONGO_PIPELINE), f"{MONGO_PIPELINE} was not created."
    with open(MONGO_PIPELINE, "r") as f:
        try:
            pipeline = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{MONGO_PIPELINE} does not contain valid JSON.")

    assert isinstance(pipeline, list), "MongoDB pipeline must be a JSON array."
    assert len(pipeline) == 2, "MongoDB pipeline must have exactly 2 stages."
    stage1, stage2 = pipeline

    assert "$match" in stage1, "First stage must be a $match stage."
    assert stage1["$match"].get("tenant_id") == tenant_id, \
        f"tenant_id in $match stage must be integer {tenant_id}."
    assert stage1["$match"].get("backup_date") == backup_date, \
        f"backup_date in $match stage must be {backup_date!r}."

    assert "$group" in stage2, "Second stage must be a $group stage."
    assert stage2["$group"].get("_id") == "$region", \
        "_id in $group stage must be '$region'."
    total_bytes = stage2["$group"].get("total_bytes")
    assert total_bytes is not None, "Missing 'total_bytes' field in $group stage."
    assert isinstance(total_bytes, dict), "total_bytes must be an accumulator object."
    assert total_bytes.get("$sum") == "$file_size_bytes", \
        "'total_bytes' must be the sum of '$file_size_bytes'."


def run_and_validate(tenant_id, backup_date, expected, index_name):
    create_database(index_name)
    for output in OUTPUTS:
        if os.path.exists(output):
            os.remove(output)

    result = subprocess.run(
        [SCRIPT_PATH, str(tenant_id), backup_date],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, \
        f"Script execution failed with error: {result.stderr}"

    assert os.path.isfile(PATHS_LOG), f"{PATHS_LOG} was not created."
    with open(PATHS_LOG, "r") as f:
        paths = [line.strip() for line in f if line.strip()]
    assert paths == expected, \
        f"Contents of {PATHS_LOG} do not match the database or are not sorted."

    assert os.path.isfile(PLAN_LOG), f"{PLAN_LOG} was not created."
    with open(PLAN_LOG, "r") as f:
        plan_content = f.read().strip()
    assert plan_content, f"{PLAN_LOG} is empty."
    upper_plan = plan_content.upper()
    assert "SCAN" in upper_plan or "SEARCH" in upper_plan, \
        f"{PLAN_LOG} does not appear to contain a valid query plan."
    assert "QUERY PLAN" in upper_plan, \
        f"{PLAN_LOG} is not raw EXPLAIN QUERY PLAN output."
    assert "CO-ROUTINE" in upper_plan and "RECURSIVE STEP" in upper_plan, \
        f"{PLAN_LOG} does not describe execution of a recursive CTE."
    assert index_name in plan_content, \
        f"{PLAN_LOG} was not generated against the current database/index."

    validate_pipeline(tenant_id, backup_date)


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_script_execution_and_outputs_for_fixed_and_hidden_inputs():
    # Preserve the original fixed invocation and assertions.
    run_and_validate(
        455,
        "2023-11-20",
        [
            "backup_root",
            "backup_root/etc",
            "backup_root/etc/passwd",
            "backup_root/var",
            "backup_root/var/log",
            "backup_root/var/log/syslog",
        ],
        token("idx_fixed_"),
    )

    # Exercise independently generated tenants and dates. A fresh unpredictable
    # index name is used for every execution so plan.log must be regenerated by
    # EXPLAIN QUERY PLAN against the current SQLite database.
    run_and_validate(
        TENANT_A,
        "2041-02-17",
        expected_paths(TENANT_A),
        token("idx_hidden_a_"),
    )
    run_and_validate(
        TENANT_B,
        "1998-12-03",
        expected_paths(TENANT_B),
        token("idx_hidden_b_"),
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
