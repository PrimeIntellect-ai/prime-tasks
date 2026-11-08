#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import sqlite3
import stat
import subprocess

import pytest

JSON_PATH = "/home/user/vulnerable_graph.json"
DB_PATH = "/home/user/infrastructure.db"
SOURCE_PATH = "/home/user/analyze.cpp"
BINARY_PATH = "/tmp/analyze_submission"


def compute_expected():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    c.execute("""
        SELECT service_id, service_name
        FROM services
        WHERE is_active = 1
          AND service_id NOT IN (
              SELECT service_id FROM backups WHERE status = 'SUCCESS'
          )
    """)
    expected_vulnerable = [
        {"service_id": row["service_id"], "service_name": row["service_name"]}
        for row in c.fetchall()
    ]

    c.execute("""
        SELECT d.provider_id, d.consumer_id
        FROM dependencies d
        JOIN services p ON d.provider_id = p.service_id
        JOIN services c ON d.consumer_id = c.service_id
        WHERE p.is_active = 1
          AND p.service_id NOT IN (
              SELECT service_id FROM backups WHERE status = 'SUCCESS'
          )
          AND c.is_active = 1
    """)
    expected_edges = [
        {"provider_id": row["provider_id"], "consumer_id": row["consumer_id"]}
        for row in c.fetchall()
    ]
    conn.close()
    return expected_vulnerable, expected_edges


def run_submission():
    if os.path.lexists(JSON_PATH):
        assert os.path.isfile(JSON_PATH), f"Output path is not a file: {JSON_PATH}"
        os.unlink(JSON_PATH)

    result = subprocess.run(
        [BINARY_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Compiled C++ program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(JSON_PATH), (
        f"Running the compiled C++ program did not create {JSON_PATH}"
    )


def load_and_compare_output():
    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File at {JSON_PATH} is not valid JSON.")

    assert "vulnerable_nodes" in data, "JSON missing 'vulnerable_nodes' key"
    assert "impacted_edges" in data, "JSON missing 'impacted_edges' key"

    expected_vulnerable, expected_edges = compute_expected()

    actual_vulnerable = sorted(
        data["vulnerable_nodes"], key=lambda x: x.get("service_id", -1)
    )
    expected_vulnerable_sorted = sorted(
        expected_vulnerable, key=lambda x: x["service_id"]
    )
    assert actual_vulnerable == expected_vulnerable_sorted, (
        f"Expected vulnerable_nodes: {expected_vulnerable_sorted}, "
        f"but got: {actual_vulnerable}"
    )

    actual_edges = sorted(
        data["impacted_edges"],
        key=lambda x: (x.get("provider_id", -1), x.get("consumer_id", -1)),
    )
    expected_edges_sorted = sorted(
        expected_edges, key=lambda x: (x["provider_id"], x["consumer_id"])
    )
    assert actual_edges == expected_edges_sorted, (
        f"Expected impacted_edges: {expected_edges_sorted}, but got: {actual_edges}"
    )


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_cpp():
    assert os.path.isfile(SOURCE_PATH), f"C++ source file missing at {SOURCE_PATH}"
    assert stat.S_ISREG(os.stat(SOURCE_PATH).st_mode), (
        f"C++ source path is not a regular file: {SOURCE_PATH}"
    )
    assert os.path.getsize(SOURCE_PATH) > 0, f"C++ source file is empty: {SOURCE_PATH}"

    result = subprocess.run(
        ["g++", "-std=c++17", SOURCE_PATH, "-lsqlite3", "-o", BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Failed to compile {SOURCE_PATH}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK), (
        "Compilation did not produce an executable"
    )
    run_submission()


def test_json_file_exists():
    assert os.path.isfile(JSON_PATH), f"Output JSON file missing at {JSON_PATH}"


def test_json_content():
    load_and_compare_output()


def test_program_recomputes_from_database():
    backup_path = "/tmp/infrastructure_verifier_backup.db"
    shutil.copy2(DB_PATH, backup_path)

    token = secrets.token_hex(12)
    service_id = 1_000_000_000 + secrets.randbelow(500_000_000)
    dependency_id = 1_000_000_000 + secrets.randbelow(500_000_000)

    try:
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        while c.execute(
            "SELECT 1 FROM services WHERE service_id = ?", (service_id,)
        ).fetchone():
            service_id += 1
        while c.execute(
            "SELECT 1 FROM dependencies WHERE dependency_id = ?", (dependency_id,)
        ).fetchone():
            dependency_id += 1

        consumer = c.execute(
            "SELECT service_id FROM services WHERE is_active = 1 ORDER BY service_id LIMIT 1"
        ).fetchone()
        assert consumer is not None, "Test database has no active consumer service"

        c.execute(
            "INSERT INTO services(service_id, service_name, is_active) VALUES (?, ?, 1)",
            (service_id, "verifier-" + token),
        )
        c.execute(
            "INSERT INTO dependencies(dependency_id, provider_id, consumer_id) VALUES (?, ?, ?)",
            (dependency_id, service_id, consumer[0]),
        )
        conn.commit()
        conn.close()

        run_submission()
        load_and_compare_output()
    finally:
        shutil.copy2(backup_path, DB_PATH)
        if os.path.exists(backup_path):
            os.unlink(backup_path)
        run_submission()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
