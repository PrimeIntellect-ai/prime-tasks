#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import uuid

SCRIPT = "/home/user/audit_query.py"
DB = "/home/user/access_graph.db"
REPORT = "/home/user/report.txt"


def run_script(username):
    result = subprocess.run(
        [sys.executable, SCRIPT, username],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"audit_query.py failed for {username!r}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_report():
    assert os.path.isfile(REPORT), f"Report file {REPORT} does not exist."
    with open(REPORT, "r", encoding="utf-8") as f:
        return [line.strip() for line in f.read().strip().splitlines() if line.strip()]


def resolve_string(node, strings):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return strings.get(node.id)
    try:
        value = ast.literal_eval(node)
    except Exception:
        return None
    return value if isinstance(value, str) else None


def test_01_audit_query_script_exists():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."


def test_02_script_contains_executed_schema_inspection_and_parameterized_recursive_cte():
    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    strings = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value_node = node.value
            value = resolve_string(value_node, strings)
            if value is None:
                continue
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                if isinstance(target, ast.Name):
                    strings[target.id] = value

    schema_inspection = False
    parameterized_recursive_cte = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not node.args:
            continue
        func_name = node.func.attr.lower() if isinstance(node.func, ast.Attribute) else ""
        if func_name not in {"execute", "executemany"}:
            continue
        sql = resolve_string(node.args[0], strings)
        if sql is None:
            continue
        normalized = " ".join(sql.lower().split())
        if ("pragma table_info" in normalized or
                "pragma table_xinfo" in normalized or
                "sqlite_master" in normalized or
                "sqlite_schema" in normalized):
            schema_inspection = True
        has_parameters = len(node.args) >= 2 or any(
            kw.arg in {"parameters", "params"} for kw in node.keywords
        )
        if "with recursive" in normalized and has_parameters:
            parameterized_recursive_cte = True

    assert schema_inspection, "The script does not execute a schema-inspection query."
    assert parameterized_recursive_cte, (
        "The script must execute its WITH RECURSIVE query with bound parameters."
    )


def test_03_run_for_alice_and_report_content():
    run_script("Alice")
    expected_lines = [
        "Analytics",
        "App-Server",
        "CI-Server",
        "Cache",
        "Queue",
    ]
    content = read_report()
    assert content == expected_lines, (
        f"Report content is incorrect. Expected {expected_lines}, but got {content}."
    )


def test_04_database_index_created():
    assert os.path.isfile(DB), f"Database file {DB} does not exist."
    conn = sqlite3.connect(DB)
    try:
        indexes = conn.execute("PRAGMA index_list('relations')").fetchall()
    finally:
        conn.close()
    assert len(indexes) > 0, "No index was created on the 'relations' table."


def test_05_dynamic_functional_traversal_and_useful_index():
    db_backup = tempfile.NamedTemporaryFile(delete=False)
    db_backup.close()
    shutil.copy2(DB, db_backup.name)
    report_existed = os.path.exists(REPORT)
    report_backup = None
    if report_existed:
        with open(REPORT, "rb") as f:
            report_backup = f.read()

    token = uuid.uuid4().hex[:10]
    user_a = f"dynamic_{token}"
    user_b = f"other_{token}"
    injection_name = f"quoted_' OR 1=1 --_{token}"
    labels = [f"A-{token}", f"B-{token}", f"C-{token}",
              f"D-{token}", f"E-{token}", f"Z-{token}"]
    other_system = f"Only-{token}"
    literal_system = f"Literal-{token}"
    leak_system = f"WrongType-{token}"

    entities = [
        (1, "User", user_a),
        (2, "User", user_b),
        (3, "User", injection_name),
        (10, "Group", f"g1_{token}"),
        (11, "Group", f"g2_{token}"),
        (12, "Group", user_b),
    ]
    entities += [(20 + i, "System", name) for i, name in enumerate(labels)]
    entities += [
        (30, "System", other_system),
        (31, "System", literal_system),
        (32, "System", leak_system),
        (40, "Group", f"not_a_system_{token}"),
    ]
    relations = [
        (1, 10), (1, 22),
        (10, 11), (11, 10),
        (10, 20), (10, 21), (10, 23),
        (11, 20), (11, 24), (11, 25), (11, 40),
        (2, 30),
        (12, 32),
        (3, 31),
    ]

    def independently_expected(username):
        by_id = {row[0]: (row[1], row[2]) for row in entities}
        starts = {row[0] for row in entities
                  if row[1] == "User" and row[2] == username}
        outgoing = {}
        for source, target in relations:
            outgoing.setdefault(source, set()).add(target)
        seen = set(starts)
        pending = list(starts)
        while pending:
            current = pending.pop()
            for target in outgoing.get(current, ()):
                if target not in seen:
                    seen.add(target)
                    pending.append(target)
        return sorted({by_id[i][1] for i in seen if by_id[i][0] == "System"})[:5]

    try:
        conn = sqlite3.connect(DB)
        try:
            for index_row in conn.execute("PRAGMA index_list('relations')").fetchall():
                index_name = index_row[1]
                escaped = index_name.replace('"', '""')
                conn.execute(f'DROP INDEX IF EXISTS "{escaped}"')
            conn.execute("DELETE FROM relations")
            conn.execute("DELETE FROM entities")
            conn.executemany("INSERT INTO entities(id, type, name) VALUES (?, ?, ?)", entities)
            conn.executemany("INSERT INTO relations(source_id, target_id) VALUES (?, ?)", relations)
            conn.commit()
        finally:
            conn.close()

        cases = [user_a, user_b, injection_name, f"missing_{token}"]
        for username in cases:
            if os.path.exists(REPORT):
                os.remove(REPORT)
            expected = independently_expected(username)
            run_script(username)
            actual = read_report()
            assert actual == expected, (
                f"Incorrect traversal result for dynamic username {username!r}: "
                f"expected {expected}, got {actual}."
            )

        conn = sqlite3.connect(DB)
        try:
            indexes = conn.execute("PRAGMA index_list('relations')").fetchall()
            assert indexes, "The script did not recreate an index on relations."
            useful = False
            for index_row in indexes:
                escaped = index_row[1].replace("'", "''")
                columns = conn.execute(f"PRAGMA index_info('{escaped}')").fetchall()
                if columns and columns[0][2] == "source_id":
                    useful = True
                    break
            assert useful, (
                "No relations index has source_id as its leading column for forward traversal."
            )
        finally:
            conn.close()
    finally:
        shutil.copy2(db_backup.name, DB)
        os.unlink(db_backup.name)
        if report_existed:
            with open(REPORT, "wb") as f:
                f.write(report_backup)
        elif os.path.exists(REPORT):
            os.remove(REPORT)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
