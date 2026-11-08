#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import re
import sqlite3
import subprocess

import pytest

SCRIPT_PATH = "/home/user/generate_plan.py"
PLAN_PATH = "/home/user/backup_plan.json"
DB_PATH = "/home/user/production.db"
BINARY_PATH = "/app/backup_scheduler"


def read_schema():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).fetchall()
        tables = {row[0] for row in rows}
        dependencies = {}
        for table in tables:
            quoted = '"' + table.replace('"', '""') + '"'
            dependencies[table] = {
                row[2] for row in conn.execute(
                    f"PRAGMA foreign_key_list({quoted})"
                ).fetchall()
            }
        return tables, dependencies
    finally:
        conn.close()


@pytest.fixture(scope="session", autouse=True)
def generate_fresh_plan():
    assert os.path.exists(SCRIPT_PATH), f"Missing required script at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file"

    tables, dependencies = read_schema()

    # Require generate_plan.py itself to create the submitted artifact.
    if os.path.lexists(PLAN_PATH):
        os.remove(PLAN_PATH)

    user = pwd.getpwnam("user")

    def drop_privileges():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            env={**os.environ, "HOME": "/home/user", "USER": "user"},
            capture_output=True,
            text=True,
            timeout=30,
            preexec_fn=drop_privileges,
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"generate_plan.py timed out: {exc}")

    assert result.returncode == 0, (
        f"generate_plan.py failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert os.path.exists(PLAN_PATH), (
        f"{SCRIPT_PATH} did not generate {PLAN_PATH}"
    )
    assert os.path.isfile(PLAN_PATH), f"Path {PLAN_PATH} is not a file"

    return tables, dependencies


def test_generate_plan_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Missing required script at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file"


def test_backup_plan_exists_and_meets_latency_threshold(generate_fresh_plan):
    all_tables, dependencies = generate_fresh_plan

    assert os.path.exists(PLAN_PATH), f"Missing backup plan at {PLAN_PATH}"
    assert os.path.isfile(PLAN_PATH), f"Path {PLAN_PATH} is not a file"
    assert os.path.exists(BINARY_PATH), f"Missing binary at {BINARY_PATH}"

    try:
        with open(PLAN_PATH, "r") as f:
            plan = json.load(f)
    except Exception as exc:
        pytest.fail(f"Invalid JSON in {PLAN_PATH}: {exc}")

    assert isinstance(plan, list), "Backup plan must be a list of phase lists"

    backed_up = set()
    for phase_number, phase in enumerate(plan, start=1):
        assert isinstance(phase, list), (
            f"Phase {phase_number} is not a list"
        )
        for table in phase:
            assert isinstance(table, str), (
                f"Phase {phase_number} contains a non-string table name"
            )
            assert table in all_tables, f"Unknown table in plan: {table}"
            assert table not in backed_up, (
                f"Table {table} appears more than once in the plan"
            )
            missing = dependencies[table] - backed_up
            assert not missing, (
                f"Table {table} is scheduled before dependencies from a previous "
                f"phase: {sorted(missing)}"
            )
            backed_up.add(table)

    assert backed_up == all_tables, (
        f"Plan does not back up every table exactly once; missing: "
        f"{sorted(all_tables - backed_up)}"
    )

    try:
        result = subprocess.run(
            [BINARY_PATH, PLAN_PATH],
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"Backup scheduler timed out: {exc}")
    except subprocess.CalledProcessError as exc:
        pytest.fail(
            f"Backup scheduler failed with exit code {exc.returncode}.\n"
            f"Stdout: {exc.stdout}\nStderr: {exc.stderr}"
        )

    output = result.stdout
    match = re.search(r"Total Latency:\s*(\d+)\s*ms", output, re.IGNORECASE)
    assert match is not None, (
        f"Could not find 'Total Latency: <number> ms' in output:\n{output}"
    )

    latency = int(match.group(1))
    threshold = 1500
    assert latency <= threshold, (
        f"Latency metric failed: measured {latency} ms, which is > threshold "
        f"{threshold} ms"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
