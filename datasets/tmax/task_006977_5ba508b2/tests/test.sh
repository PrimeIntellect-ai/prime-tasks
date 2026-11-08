#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import pytest

NODES_PATH = "/home/user/nodes.csv"
EDGES_PATH = "/home/user/edges.csv"
SOURCE_PATH = "/home/user/map_backup.c"
BINARY_PATH = "/home/user/map_backup"
BACKUP_PATH = "/home/user/backup.json"


def test_backup_json_exists_and_valid():
    file_path = BACKUP_PATH
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    expected_data = {
        "services": [
            {
                "id": "srv_auth",
                "dependencies": [
                    "srv_cache",
                    "srv_db"
                ]
            },
            {
                "id": "srv_cache",
                "dependencies": []
            },
            {
                "id": "srv_db",
                "dependencies": []
            },
            {
                "id": "srv_queue",
                "dependencies": [
                    "srv_db"
                ]
            }
        ]
    }

    assert data == expected_data, f"JSON content in {file_path} does not match the expected structure."


def test_c_program_exists():
    file_path = SOURCE_PATH
    assert os.path.isfile(file_path), f"C source file {file_path} does not exist."


def test_binary_exists():
    file_path = BINARY_PATH
    assert os.path.isfile(file_path), f"Compiled binary {file_path} does not exist."
    assert os.access(file_path, os.X_OK), f"File {file_path} is not executable."


def expected_document(nodes, edges):
    service_ids = sorted(node_id for node_id, node_type, _ in nodes if node_type == "Service")
    return {
        "services": [
            {
                "id": service_id,
                "dependencies": sorted(
                    target_id
                    for source_id, target_id, relationship in edges
                    if source_id == service_id and relationship == "DEPENDS_ON"
                ),
            }
            for service_id in service_ids
        ]
    }


def write_fixture(nodes, edges):
    with open(NODES_PATH, "w", newline="") as f:
        f.write("id,type,name\n")
        for row in nodes:
            f.write(",".join(row) + "\n")

    with open(EDGES_PATH, "w", newline="") as f:
        f.write("source_id,target_id,relationship\n")
        for row in edges:
            f.write(",".join(row) + "\n")


def run_and_check(nodes, edges):
    write_fixture(nodes, edges)
    if os.path.exists(BACKUP_PATH):
        os.remove(BACKUP_PATH)

    result = subprocess.run(
        [BINARY_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"map_backup exited with {result.returncode}: {result.stderr}"
    assert os.path.isfile(BACKUP_PATH), "Running map_backup did not produce /home/user/backup.json."

    try:
        with open(BACKUP_PATH, "r") as f:
            actual = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Running map_backup produced invalid JSON: {exc}")

    assert actual == expected_document(nodes, edges)


def test_submitted_source_compiles_and_handles_generated_inputs():
    compile_result = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, f"map_backup.c failed to compile: {compile_result.stderr}"
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK)

    original_nodes = [
        ("srv_auth", "Service", "Authenticator"),
        ("srv_db", "Service", "MainDB"),
        ("srv_cache", "Service", "RedisCache"),
        ("srv_queue", "Service", "RabbitMQ"),
        ("srv_ui", "Frontend", "UserInterface"),
    ]
    original_edges = [
        ("srv_auth", "srv_db", "DEPENDS_ON"),
        ("srv_auth", "srv_cache", "DEPENDS_ON"),
        ("srv_queue", "srv_db", "DEPENDS_ON"),
        ("srv_ui", "srv_auth", "CALLS"),
    ]
    run_and_check(original_nodes, original_edges)

    token = secrets.token_hex(6)
    ids = [f"svc_{token}_{suffix}" for suffix in ("zeta", "alpha", "middle", "empty")]
    external_id = f"external_{token}"
    frontend_id = f"frontend_{token}"
    nodes = [
        (ids[0], "Service", "ZetaService"),
        (frontend_id, "Frontend", "WebUI"),
        (ids[2], "Service", "MiddleService"),
        (external_id, "Database", "ExternalStore"),
        (ids[3], "Service", "NoDependencies"),
        (ids[1], "Service", "AlphaService"),
    ]
    edges = [
        (ids[0], ids[2], "DEPENDS_ON"),
        (ids[0], ids[1], "DEPENDS_ON"),
        (ids[1], external_id, "DEPENDS_ON"),
        (ids[1], ids[0], "CALLS"),
        (frontend_id, ids[0], "DEPENDS_ON"),
        (ids[2], ids[1], "DEPENDS_ON"),
    ]
    rng = random.SystemRandom()
    rng.shuffle(nodes)
    rng.shuffle(edges)
    run_and_check(nodes, edges)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
