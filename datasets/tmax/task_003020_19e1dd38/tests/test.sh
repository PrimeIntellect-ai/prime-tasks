#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/analyze_impact.py"
OUTPUT_PATH = "/home/user/impact.json"
DB_PATH = "/home/user/architecture.db"


def test_output_json_exists_and_correct():
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file."

    with open(OUTPUT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{OUTPUT_PATH} does not contain valid JSON.")

    assert "target" in data, "JSON output is missing the 'target' key."
    assert data["target"] == "PaymentGateway", f"Expected target 'PaymentGateway', got '{data['target']}'."

    assert "impacted" in data, "JSON output is missing the 'impacted' key."
    expected_impacted = ["AnalyticsService", "CartService", "OrderService"]

    assert isinstance(data["impacted"], list), "'impacted' should be a list."
    assert data["impacted"] == expected_impacted, f"Expected impacted list {expected_impacted}, got {data['impacted']}."


def test_script_exists_and_uses_parameterized_queries():
    assert os.path.exists(SCRIPT_PATH), f"Script file {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    try:
        tree = ast.parse(content)
    except SyntaxError:
        pytest.fail(f"Script {SCRIPT_PATH} contains syntax errors.")

    # Preserve the original checks.
    assert "?" in content or ":" in content, "Script does not appear to use strictly parameterized queries (missing '?' or ':name' placeholders)."
    assert "sqlite3" in content, "Script does not appear to import sqlite3."

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assignments[target.id] = node.value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.value is not None:
            assignments[node.target.id] = node.value

    def constant_string(node, seen=None):
        seen = set() if seen is None else seen
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.Name) and node.id in assignments and node.id not in seen:
            return constant_string(assignments[node.id], seen | {node.id})
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            left = constant_string(node.left, seen)
            right = constant_string(node.right, seen)
            if left is not None and right is not None:
                return left + right
        return None

    def unsafe_sql_expression(node, seen=None):
        seen = set() if seen is None else seen
        if isinstance(node, ast.JoinedStr):
            return True
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Mod):
            return True
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "format":
            return True
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            return constant_string(node, seen) is None
        if isinstance(node, ast.Name) and node.id in assignments and node.id not in seen:
            return unsafe_sql_expression(assignments[node.id], seen | {node.id})
        return False

    execute_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "execute"
        and node.args
    ]
    assert execute_calls, "Script does not execute any SQLite query."

    for call in execute_calls:
        assert not unsafe_sql_expression(call.args[0]), "SQL passed to execute() must not be built with interpolation, formatting, or dynamic concatenation."

    parameterized = False
    for call in execute_calls:
        has_parameters = len(call.args) >= 2 or any(k.arg == "parameters" for k in call.keywords)
        sql = constant_string(call.args[0])
        has_placeholder = sql is not None and ("?" in sql or re.search(r":[A-Za-z_][A-Za-z0-9_]*", sql))
        if has_parameters and has_placeholder:
            parameterized = True
            break
    assert parameterized, "No execute() call supplies parameters separately from SQL containing a placeholder."


def _create_controlled_database(path, names):
    conn = sqlite3.connect(path)
    try:
        conn.executescript("""
            CREATE TABLE services (
                id INTEGER PRIMARY KEY,
                service_name TEXT UNIQUE NOT NULL
            );
            CREATE TABLE dependencies (
                caller_id INTEGER,
                callee_id INTEGER,
                is_critical BOOLEAN,
                PRIMARY KEY (caller_id, callee_id),
                FOREIGN KEY (caller_id) REFERENCES services(id),
                FOREIGN KEY (callee_id) REFERENCES services(id)
            );
        """)
        conn.executemany(
            "INSERT INTO services(id, service_name) VALUES (?, ?)",
            [(i + 1, name) for i, name in enumerate(names)],
        )
        ids = {name: i + 1 for i, name in enumerate(names)}
        target, a, b, c, noncritical, e, f, isolated = names
        edges = [
            (a, target, 1),
            (b, a, 1),
            (c, b, 1),
            (noncritical, target, 0),
            (e, a, 1),
            (target, b, 1),
            (f, target, 1),
            (isolated, c, 0),
        ]
        conn.executemany(
            "INSERT INTO dependencies(caller_id, callee_id, is_critical) VALUES (?, ?, ?)",
            [(ids[caller], ids[callee], critical) for caller, callee, critical in edges],
        )
        conn.commit()
    finally:
        conn.close()


def _derive_expected(target):
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            """SELECT caller.service_name
               FROM dependencies d
               JOIN services caller ON caller.id = d.caller_id
               JOIN services callee ON callee.id = d.callee_id
               WHERE callee.service_name = ? AND d.is_critical = 1""",
            (target,),
        ).fetchall()
        depth1 = {row[0] for row in rows}
        impacted = set(depth1)
        for service in depth1:
            rows = conn.execute(
                """SELECT caller.service_name
                   FROM dependencies d
                   JOIN services caller ON caller.id = d.caller_id
                   JOIN services callee ON callee.id = d.callee_id
                   WHERE callee.service_name = ? AND d.is_critical = 1""",
                (service,),
            ).fetchall()
            impacted.update(row[0] for row in rows)
        impacted.discard(target)
        return {"target": target, "impacted": sorted(impacted)}
    finally:
        conn.close()


def _run_and_check(target):
    if os.path.lexists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)
    result = subprocess.run(
        ["python3", SCRIPT_PATH, target],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Script failed for target {target!r}: {result.stderr}"
    assert os.path.isfile(OUTPUT_PATH), "Script did not generate /home/user/impact.json."
    try:
        with open(OUTPUT_PATH, "r") as f:
            actual = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Script generated invalid JSON for target {target!r}: {exc}")
    assert actual == _derive_expected(target)


def test_script_executes_correctly_for_unseen_targets_and_exact_arity():
    token = uuid.uuid4().hex
    names = [
        f"Target_'--_{token}",
        f"Alpha_{token}",
        f"Beta_{token}",
        f"Gamma_{token}",
        f"NonCritical_{token}",
        f"Echo_{token}",
        f"Foxtrot_{token}",
        f"Isolated_{token}",
    ]

    with tempfile.TemporaryDirectory() as tempdir:
        db_backup = os.path.join(tempdir, "architecture.db.backup")
        controlled_db = os.path.join(tempdir, "controlled.db")
        shutil.copy2(DB_PATH, db_backup)
        _create_controlled_database(controlled_db, names)

        output_existed = os.path.isfile(OUTPUT_PATH)
        output_backup = os.path.join(tempdir, "impact.json.backup")
        if output_existed:
            shutil.copy2(OUTPUT_PATH, output_backup)

        try:
            for target in (names[0], names[1], names[7]):
                shutil.copy2(controlled_db, DB_PATH)
                expected = _derive_expected(target)
                _run_and_check(target)
                with open(OUTPUT_PATH, "r") as f:
                    assert json.load(f) == expected

            no_arg = subprocess.run(["python3", SCRIPT_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
            assert no_arg.returncode != 0, "Script must reject invocation without a target argument."

            extra_arg = subprocess.run(["python3", SCRIPT_PATH, names[0], "extra"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
            assert extra_arg.returncode != 0, "Script must reject invocation with more than one argument."
        finally:
            shutil.copy2(db_backup, DB_PATH)
            if os.path.lexists(OUTPUT_PATH):
                os.unlink(OUTPUT_PATH)
            if output_existed:
                shutil.copy2(output_backup, OUTPUT_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
