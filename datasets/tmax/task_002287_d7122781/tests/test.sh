#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import sqlite3
import subprocess

import pytest

SCRIPT_PATH = "/home/user/etl_process.sh"
DB_PATH = "/home/user/etl_data.db"
PROD_JSON_PATH = "/home/user/prod_graph.json"
DEV_JSON_PATH = "/home/user/dev_graph.json"


def run_script(*args):
    return subprocess.run(
        [SCRIPT_PATH, *args], capture_output=True, text=True, timeout=15
    )


def load_json(path):
    assert os.path.exists(path), f"Output file {path} does not exist."
    with open(path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")


def derive_expected(env):
    con = sqlite3.connect(DB_PATH)
    try:
        servers = {
            row[0]: (row[1], row[2])
            for row in con.execute("SELECT id, hostname, env FROM servers")
        }
        latest = {}
        for source_id, target_id, updated_at, status in con.execute(
            "SELECT source_id, target_id, updated_at, status FROM connections_raw"
        ):
            key = (source_id, target_id)
            if key not in latest or updated_at > latest[key][0]:
                latest[key] = (updated_at, status)

        targets_by_source = {}
        for (source_id, target_id), (_, status) in latest.items():
            if status != "active":
                continue
            if source_id not in servers or target_id not in servers:
                continue
            source_hostname, source_env = servers[source_id]
            if source_env == env:
                targets_by_source.setdefault(source_hostname, []).append(
                    servers[target_id][0]
                )

        return {
            source: {
                "outgoing_count": len(targets),
                "targets": sorted(targets),
            }
            for source, targets in targets_by_source.items()
        }
    finally:
        con.close()


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_prod_graph_json_contents():
    assert os.path.exists(PROD_JSON_PATH), (
        f"Output file {PROD_JSON_PATH} does not exist. "
        "Did you run the script for the 'prod' environment?"
    )
    data = load_json(PROD_JSON_PATH)
    expected = {
        "db-prod-01": {
            "outgoing_count": 1,
            "targets": ["cache-prod-01"],
        },
        "web-prod-01": {
            "outgoing_count": 2,
            "targets": ["db-prod-01", "web-dev-01"],
        },
    }
    assert data == expected, (
        f"Contents of {PROD_JSON_PATH} do not match the expected graph output "
        "for the 'prod' environment."
    )


def test_script_dynamic_execution():
    result = run_script("dev")
    assert result.returncode == 0, (
        f"Script failed when executed with 'dev' argument. Stderr: {result.stderr}"
    )
    assert os.path.exists(DEV_JSON_PATH), (
        f"Script did not generate {DEV_JSON_PATH} when run with 'dev' argument."
    )
    data = load_json(DEV_JSON_PATH)
    expected = {
        "web-dev-01": {
            "outgoing_count": 1,
            "targets": ["db-prod-01"],
        }
    }
    assert data == expected, (
        f"Contents of {DEV_JSON_PATH} do not match the expected graph output "
        "for the 'dev' environment."
    )


def test_requires_exactly_one_argument():
    no_args = run_script()
    assert no_args.returncode != 0, "Script accepted zero arguments."
    extra_arg = run_script("prod", "unexpected")
    assert extra_arg.returncode != 0, "Script accepted more than one argument."


def test_reads_database_and_handles_unseen_data():
    token = secrets.token_hex(6)
    env = f"audit_{token}"
    output_path = f"/home/user/{env}_graph.json"
    backup_path = f"/tmp/etl_data_{token}.db"
    shutil.copy2(DB_PATH, backup_path)

    try:
        con = sqlite3.connect(DB_PATH)
        next_id = con.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM servers").fetchone()[0]
        source_a, source_b, target_a, target_b, target_c = range(next_id, next_id + 5)
        host_a = f"source-a-{token}"
        host_b = f"source-b-{token}"
        host_ta = f"alpha-target-{token}"
        host_tb = f"beta-target-{token}"
        host_tc = f"gamma-target-{token}"

        con.executemany(
            "INSERT INTO servers(id, hostname, env) VALUES (?, ?, ?)",
            [
                (source_a, host_a, env),
                (source_b, host_b, env),
                (target_a, host_ta, "other"),
                (target_b, host_tb, env),
                (target_c, host_tc, "third"),
            ],
        )
        con.executemany(
            "INSERT INTO connections_raw(source_id, target_id, updated_at, status) "
            "VALUES (?, ?, ?, ?)",
            [
                (source_a, target_a, 100, "inactive"),
                (source_a, target_a, 300, "active"),
                (source_a, target_b, 150, "active"),
                (source_a, target_b, 350, "inactive"),
                (source_a, target_c, 250, "active"),
                (source_b, target_b, 400, "active"),
                (target_a, source_a, 500, "active"),
            ],
        )
        con.commit()
        con.close()

        first_expected = derive_expected(env)
        first = run_script(env)
        assert first.returncode == 0, (
            f"Script failed for an unseen environment. Stderr: {first.stderr}"
        )
        assert load_json(output_path) == first_expected

        con = sqlite3.connect(DB_PATH)
        con.execute(
            "INSERT INTO connections_raw(source_id, target_id, updated_at, status) "
            "VALUES (?, ?, ?, ?)",
            (source_a, target_b, 1000000000000, "active"),
        )
        con.execute(
            "INSERT INTO connections_raw(source_id, target_id, updated_at, status) "
            "VALUES (?, ?, ?, ?)",
            (source_b, target_b, 1000000000001, "inactive"),
        )
        con.commit()
        con.close()

        second_expected = derive_expected(env)
        assert second_expected != first_expected
        second = run_script(env)
        assert second.returncode == 0, (
            f"Script failed after the database changed. Stderr: {second.stderr}"
        )
        assert load_json(output_path) == second_expected
    finally:
        if os.path.exists(backup_path):
            os.replace(backup_path, DB_PATH)
        if os.path.exists(output_path):
            os.remove(output_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
