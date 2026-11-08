#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH="/opt/cargo/bin:${PATH}"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import sqlite3
import subprocess
import pytest

DB_PATH = "/home/user/compliance.db"
PROJECT_PATH = "/home/user/auditor"
OPTIMIZE_PATH = "/home/user/optimize.sql"


def drop_user_indexes():
    conn = sqlite3.connect(DB_PATH)
    try:
        indexes = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='logs' AND sql IS NOT NULL"
        ).fetchall()
        for (name,) in indexes:
            conn.execute('DROP INDEX "' + name.replace('"', '""') + '"')
        conn.commit()
    finally:
        conn.close()


def expected_report(uid):
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            """
            SELECT l.target_system, COUNT(*)
            FROM users AS u
            JOIN logs AS l ON u.uid = l.uid
            WHERE l.uid = ? AND l.success = 0 AND u.clearance_level < 3
            GROUP BY l.target_system
            ORDER BY l.target_system ASC
            """,
            (uid,),
        ).fetchall()
    finally:
        conn.close()
    return [
        {"target_system": target, "unauthorized_attempts": count}
        for target, count in rows
    ]


def run_tool(argument):
    return subprocess.run(
        ["cargo", "run", "--release", "--quiet", "--", str(argument)],
        cwd=PROJECT_PATH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )


def assert_report(uid):
    report_path = f"/home/user/report_{uid}.json"
    assert os.path.isfile(report_path), f"Tool did not create {report_path}."
    raw = open(report_path, "r", encoding="utf-8").read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Tool produced invalid JSON in {report_path}: {exc}")

    expected = expected_report(uid)
    assert data == expected, f"Expected {expected}, got {data}."
    assert isinstance(data, list), "The report must be a JSON array."
    assert [item["target_system"] for item in data] == sorted(
        item["target_system"] for item in data
    ), "Report rows are not sorted alphabetically by target_system."
    for item in data:
        assert set(item) == {"target_system", "unauthorized_attempts"}
        assert isinstance(item["target_system"], str)
        assert isinstance(item["unauthorized_attempts"], int)


def test_00_build_and_execute_tool_on_unseen_data():
    cargo_toml = os.path.join(PROJECT_PATH, "Cargo.toml")
    main_rs = os.path.join(PROJECT_PATH, "src", "main.rs")
    assert os.path.isfile(cargo_toml)
    assert os.path.isfile(main_rs)
    assert os.path.isfile(OPTIMIZE_PATH)

    build = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT_PATH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert build.returncode == 0, f"Rust project failed to build:\n{build.stdout}\n{build.stderr}"

    source = open(main_rs, "r", encoding="utf-8").read()
    compact_source = re.sub(r"\s+", "", source)
    parameter_binding_markers = (
        "params![",
        "named_params![",
        ".bind(",
        "params_from_iter",
        "raw_bind_parameter",
        "sqlite3_bind",
        "query_map([",
        "query([",
    )
    assert any(marker in compact_source for marker in parameter_binding_markers), (
        "Rust source does not appear to bind the uid as a SQL parameter."
    )

    conn = sqlite3.connect(DB_PATH)
    try:
        while True:
            uid = 200000 + secrets.randbelow(500000000)
            if conn.execute("SELECT 1 FROM users WHERE uid IN (?, ?)", (uid, uid + 1)).fetchone() is None:
                break
        low_uid = uid
        high_uid = uid + 1
        conn.execute("INSERT INTO users(uid, username, clearance_level) VALUES (?, ?, ?)", (low_uid, "dynamic_low", 1))
        conn.execute("INSERT INTO users(uid, username, clearance_level) VALUES (?, ?, ?)", (high_uid, "dynamic_high", 5))
        dynamic_logs = [
            (low_uid, "READ", "Alpha ' Gate", 1800000001, 0),
            (low_uid, "WRITE", "Alpha ' Gate", 1800000002, 0),
            (low_uid, "READ", "Middle System", 1800000003, 1),
            (low_uid, "DELETE", "Zulu", 1800000004, 0),
            (low_uid, "READ", "Ω System", 1800000005, 0),
            (high_uid, "READ", "Admin Failure", 1800000006, 0),
        ]
        conn.executemany(
            "INSERT INTO logs(uid, action, target_system, timestamp, success) VALUES (?, ?, ?, ?, ?)",
            dynamic_logs,
        )
        conn.commit()
    finally:
        conn.close()

    original_sql = open(OPTIMIZE_PATH, "r", encoding="utf-8").read()
    marker_index = "verifier_runtime_" + secrets.token_hex(8)
    try:
        with open(OPTIMIZE_PATH, "w", encoding="utf-8") as f:
            f.write(f'CREATE INDEX IF NOT EXISTS "{marker_index}" ON logs(uid, success);\n')

        for test_uid in (low_uid, high_uid):
            drop_user_indexes()
            report_path = f"/home/user/report_{test_uid}.json"
            if os.path.exists(report_path):
                os.remove(report_path)
            result = run_tool(test_uid)
            assert result.returncode == 0, (
                f"Tool failed for uid {test_uid}:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            assert_report(test_uid)

            conn = sqlite3.connect(DB_PATH)
            try:
                row = conn.execute(
                    "SELECT sql FROM sqlite_master WHERE type='index' AND name=? AND tbl_name='logs'",
                    (marker_index,),
                ).fetchone()
                assert row is not None, "Tool did not execute the current optimize.sql script."
                columns = [r[2] for r in conn.execute(f'PRAGMA index_info("{marker_index}")')]
                assert columns == ["uid", "success"]
            finally:
                conn.close()

        injection = f"{low_uid} OR 1=1"
        result = run_tool(injection)
        assert result.returncode != 0, "CLI accepted a non-integer, SQL-like uid argument."
    finally:
        with open(OPTIMIZE_PATH, "w", encoding="utf-8") as f:
            f.write(original_sql)

    drop_user_indexes()
    report_42 = "/home/user/report_42.json"
    if os.path.exists(report_42):
        os.remove(report_42)
    result = run_tool(42)
    assert result.returncode == 0, f"Tool failed for uid 42:\n{result.stdout}\n{result.stderr}"
    assert_report(42)


def test_optimize_sql_exists_and_valid():
    """Verify that optimize.sql exists and contains a valid CREATE INDEX statement."""
    sql_path = "/home/user/optimize.sql"
    assert os.path.isfile(sql_path), f"Optimization script not found at {sql_path}."

    with open(sql_path, "r") as f:
        content = f.read().lower()

    assert "create index" in content, "optimize.sql must contain a CREATE INDEX statement."
    assert "on logs" in content or "on \"logs\"" in content or "on `logs`" in content, "The index must be created on the 'logs' table."
    assert "uid" in content, "The index must include the 'uid' column."
    assert "success" in content, "The index must include the 'success' column."


def test_rust_project_exists():
    """Verify that the Rust project was initialized."""
    cargo_toml = "/home/user/auditor/Cargo.toml"
    main_rs = "/home/user/auditor/src/main.rs"

    assert os.path.isfile(cargo_toml), f"Rust project not found: {cargo_toml} is missing."
    assert os.path.isfile(main_rs), f"Rust source not found: {main_rs} is missing."


def test_report_json_exists_and_valid():
    """Verify that the report JSON file is generated correctly for uid 42."""
    report_path = "/home/user/report_42.json"
    assert os.path.isfile(report_path), f"Report file not found at {report_path}."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} does not contain valid JSON.")

    assert isinstance(data, list), "The JSON output must be an array of objects."

    expected = [
        {"target_system": "Vault A", "unauthorized_attempts": 2},
        {"target_system": "Vault B", "unauthorized_attempts": 1},
        {"target_system": "Vault C", "unauthorized_attempts": 3}
    ]

    data_sorted = sorted(data, key=lambda x: x.get("target_system", ""))
    expected_sorted = sorted(expected, key=lambda x: x["target_system"])

    assert data_sorted == expected_sorted, f"Report data mismatch. Expected {expected_sorted}, got {data_sorted}."


def test_db_index_created():
    """Verify that the index was actually applied to the database."""
    db_path = "/home/user/compliance.db"
    assert os.path.isfile(db_path), f"Database file missing at {db_path}."

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='logs'")
    indexes = cur.fetchall()
    conn.close()

    user_indexes = [idx for idx in indexes if idx[1] is not None]

    assert len(user_indexes) > 0, "No custom index was found on the 'logs' table in the database."

    valid_index_found = False
    for name, sql in user_indexes:
        sql_lower = sql.lower()
        if "uid" in sql_lower and "success" in sql_lower:
            valid_index_found = True
            break

    assert valid_index_found, "The index applied to the database does not include both 'uid' and 'success' columns."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
