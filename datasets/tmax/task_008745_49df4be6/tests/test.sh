#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import subprocess

DB = "/home/user/architecture.db"
SCRIPT = "/home/user/audit.py"
VULNS = "/home/user/vulnerabilities.txt"
PLAN = "/home/user/query_plan.txt"
ALLOWED = {"ASSUMES", "CALLS", "READS"}


def install_database(entities, relations):
    for path in (DB, VULNS, PLAN):
        if os.path.exists(path):
            os.remove(path)

    conn = sqlite3.connect(DB)
    conn.execute("CREATE TABLE entities (id TEXT PRIMARY KEY, type TEXT, is_pii INTEGER, region TEXT)")
    conn.execute("CREATE TABLE relations (source TEXT, relation TEXT, target TEXT)")
    conn.executemany("INSERT INTO entities VALUES (?, ?, ?, ?)", entities)
    conn.executemany("INSERT INTO relations VALUES (?, ?, ?)", relations)
    conn.commit()
    conn.close()


def expected_vulnerabilities(entities, relations):
    reachable = {row[0] for row in entities if row[1] == "ExternalUser"}
    outgoing = {}
    for source, relation, target in relations:
        if relation in ALLOWED:
            outgoing.setdefault(source, []).append(target)

    pending = list(reachable)
    while pending:
        source = pending.pop()
        for target in outgoing.get(source, []):
            if target not in reachable:
                reachable.add(target)
                pending.append(target)

    return sorted(row[0] for row in entities if row[2] == 1 and row[0] in reachable)


def table_snapshot():
    conn = sqlite3.connect(DB)
    entities = conn.execute("SELECT id, type, is_pii, region FROM entities ORDER BY id").fetchall()
    relations = conn.execute("SELECT source, relation, target FROM relations ORDER BY source, relation, target").fetchall()
    conn.close()
    return entities, relations


def index_details(table):
    conn = sqlite3.connect(DB)
    result = []
    for row in conn.execute(f"PRAGMA index_list('{table}')").fetchall():
        name = row[1]
        columns = [info[2] for info in conn.execute(f"PRAGMA index_info('{name}')").fetchall()]
        result.append((name, columns))
    conn.close()
    return result


def run_and_check(entities, relations, fixed_expected=None):
    install_database(entities, relations)
    before = table_snapshot()

    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"audit.py failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert table_snapshot() == before, "audit.py modified data in entities or relations"

    assert os.path.isfile(VULNS), f"{VULNS} does not exist. The script must create this file."
    with open(VULNS, "r") as f:
        content = [line.strip() for line in f.read().strip().splitlines() if line.strip()]

    expected = expected_vulnerabilities(entities, relations)
    if fixed_expected is not None:
        assert content == fixed_expected, (
            f"vulnerabilities.txt contains incorrect entities. Expected {fixed_expected}, got {content}"
        )
    assert content == expected, f"Expected dynamically derived vulnerabilities {expected}, got {content}"
    assert content == sorted(set(content)), "Vulnerability IDs must be unique and sorted alphabetically"

    assert os.path.isfile(DB), f"{DB} does not exist."
    relation_indexes = index_details("relations")
    assert len(relation_indexes) > 0, (
        "No indexes found on the 'relations' table. You must create an index to optimize the query."
    )
    entity_indexes = index_details("entities")
    custom_entity_indexes = [idx for idx in entity_indexes if not idx[0].startswith("sqlite_autoindex_")]
    assert len(custom_entity_indexes) > 0, (
        "No custom indexes found on the 'entities' table. You must create an index to optimize the query."
    )
    assert any(columns and columns[0] == "source" for _, columns in relation_indexes), (
        "The relations table needs an index whose leading column is source for recursive expansion"
    )

    assert os.path.isfile(PLAN), f"{PLAN} does not exist. The script must save the EXPLAIN QUERY PLAN output."
    with open(PLAN, "r") as f:
        plan_content = f.read().upper()
    assert "SEARCH" in plan_content or "USING INDEX" in plan_content or "COVERING INDEX" in plan_content, (
        "query_plan.txt does not demonstrate index usage. Expected to see 'SEARCH' or index scans in the plan."
    )
    assert "RECURSIVE" in plan_content or "CO-ROUTINE" in plan_content, (
        "query_plan.txt does not contain the execution plan for a recursive CTE"
    )
    relation_custom_names = [name.upper() for name, _ in relation_indexes if not name.startswith("sqlite_autoindex_")]
    entity_custom_names = [name.upper() for name, _ in custom_entity_indexes]
    assert any(name in plan_content for name in relation_custom_names), (
        "The saved query plan does not show use of the created relations index"
    )
    assert any(name in plan_content for name in entity_custom_names), (
        "The saved query plan does not show use of the created entities index"
    )


def test_audit_script_and_outputs():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist. You must write your code in this file."
    with open(SCRIPT, "r", errors="replace") as f:
        source = f.read()
    assert re.search(r"\bWITH\s+RECURSIVE\b", source, re.IGNORECASE), (
        "audit.py must contain a SQL query using WITH RECURSIVE"
    )
    assert re.search(r"\bEXPLAIN\s+QUERY\s+PLAN\b", source, re.IGNORECASE), (
        "audit.py must execute EXPLAIN QUERY PLAN for its recursive query"
    )

    original_entities = [
        ('user_ext_1', 'ExternalUser', 0, 'US'),
        ('user_ext_2', 'ExternalUser', 0, 'EU'),
        ('user_int_1', 'InternalUser', 0, 'US'),
        ('role_web', 'Role', 0, 'US'),
        ('role_admin', 'Role', 0, 'US'),
        ('svc_frontend', 'Service', 0, 'US'),
        ('svc_backend', 'Service', 0, 'US'),
        ('db_public', 'Database', 0, 'US'),
        ('db_users', 'Database', 1, 'US'),
        ('db_financial', 'Database', 1, 'EU'),
    ] + [(f'noise_ent_{i}', 'Service', 0, 'US') for i in range(1000)]
    original_relations = [
        ('user_ext_1', 'ASSUMES', 'role_web'),
        ('user_ext_2', 'KNOWS', 'user_ext_1'),
        ('role_web', 'CALLS', 'svc_frontend'),
        ('svc_frontend', 'CALLS', 'svc_backend'),
        ('svc_backend', 'READS', 'db_public'),
        ('svc_backend', 'READS', 'db_users'),
        ('user_int_1', 'ASSUMES', 'role_admin'),
        ('role_admin', 'READS', 'db_financial'),
    ] + [(f'noise_ent_{i}', 'CALLS', f'noise_ent_{i+1}') for i in range(999)]
    run_and_check(original_entities, original_relations, fixed_expected=["db_users"])

    dynamic_entities = [
        ('outside_a', 'ExternalUser', 0, 'US'),
        ('outside_b', 'ExternalUser', 0, 'EU'),
        ('inside', 'InternalUser', 0, 'US'),
        ('role_a', 'Role', 0, 'US'),
        ('service_a', 'Service', 0, 'US'),
        ('pii_alpha', 'Database', 1, 'US'),
        ('pii_zeta', 'Database', 1, 'US'),
        ('pii_invalid_edge', 'Database', 1, 'US'),
        ('pii_internal_only', 'Database', 1, 'US'),
        ('pii_wrong_direction', 'Database', 1, 'US'),
    ] + [(f'dyn_noise_{i}', 'Service', 0, 'US') for i in range(600)]
    dynamic_relations = [
        ('outside_a', 'ASSUMES', 'role_a'),
        ('role_a', 'CALLS', 'service_a'),
        ('service_a', 'CALLS', 'role_a'),
        ('service_a', 'READS', 'pii_zeta'),
        ('outside_b', 'READS', 'pii_alpha'),
        ('outside_a', 'KNOWS', 'pii_invalid_edge'),
        ('inside', 'READS', 'pii_internal_only'),
        ('pii_wrong_direction', 'READS', 'outside_a'),
    ] + [(f'dyn_noise_{i}', 'CALLS', f'dyn_noise_{i+1}') for i in range(599)]
    run_and_check(dynamic_entities, dynamic_relations)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
