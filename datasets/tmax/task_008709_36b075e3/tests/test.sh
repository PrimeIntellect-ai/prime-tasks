#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess
from pathlib import Path

import pytest


def test_audit_script_exists_and_executable():
    script_path = "/home/user/audit.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_charlie_access_json():
    output_path = "/home/user/charlie_access.json"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    expected_content = """[
  {"user": "u_charlie", "resource": "res_db_main"},
  {"user": "u_charlie", "resource": "res_server_1"}
]"""

    with open(output_path, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {output_path} does not match the strict expected JSON format."


def test_audit_script_functionality_bob():
    script_path = "/home/user/audit.sh"

    try:
        result = subprocess.run([script_path, "u_bob"], capture_output=True, text=True, timeout=5)
    except subprocess.TimeoutExpired:
        pytest.fail("Script timed out, possible infinite loop.")

    assert result.returncode == 0, "Script failed to execute successfully for u_bob."

    expected_content = """[
  {"user": "u_bob", "resource": "res_dashboard"}
]"""

    assert result.stdout.strip() == expected_content, "Script output for u_bob does not match the expected JSON format."


def test_audit_script_functionality_alice():
    script_path = "/home/user/audit.sh"

    try:
        result = subprocess.run([script_path, "u_alice"], capture_output=True, text=True, timeout=5)
    except subprocess.TimeoutExpired:
        pytest.fail("Script timed out, possible infinite loop.")

    assert result.returncode == 0, "Script failed to execute successfully for u_alice."

    expected_content = """[
  {"user": "u_alice", "resource": "res_db_main"},
  {"user": "u_alice", "resource": "res_server_1"}
]"""

    assert result.stdout.strip() == expected_content, "Script output for u_alice does not match the expected JSON format."


def oracle_output(user, edges):
    reachable = {user}
    pending = [user]
    resources = set()

    while pending:
        node = pending.pop()
        for source, target, edge_type in edges:
            if source != node:
                continue
            if edge_type == "CAN_ACCESS":
                resources.add(target)
            elif edge_type in ("HAS_ROLE", "IN_GROUP") and target not in reachable:
                reachable.add(target)
                pending.append(target)

    lines = ["["]
    ordered = sorted(resources)
    for index, resource in enumerate(ordered):
        suffix = "," if index < len(ordered) - 1 else ""
        lines.append("  " + json.dumps({"user": user, "resource": resource}) + suffix)
    lines.append("]")
    return "\n".join(lines)


def test_randomized_graph_traversal_and_cycle_handling():
    script_path = "/home/user/audit.sh"
    edges_path = Path("/home/user/edges.csv")
    original_edges = edges_path.read_bytes()
    token = secrets.token_hex(10)
    user = f"user_{token}"

    def run_case(edges):
        with edges_path.open("w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["source", "target", "type"])
            writer.writerows(edges)

        try:
            result = subprocess.run([script_path, user], capture_output=True, text=True, timeout=5)
        except subprocess.TimeoutExpired:
            pytest.fail("Script timed out on a dynamically generated cyclic graph.")

        assert result.returncode == 0, "Script failed on a dynamically generated graph."
        assert result.stdout.strip() == oracle_output(user, edges), \
            "Script did not correctly traverse the dynamically generated graph."

    first_edges = [
        (user, f"role_{token}", "HAS_ROLE"),
        (f"role_{token}", f"group_one_{token}", "IN_GROUP"),
        (f"group_one_{token}", f"group_two_{token}", "IN_GROUP"),
        (f"group_two_{token}", f"group_three_{token}", "HAS_ROLE"),
        (f"group_three_{token}", f"group_one_{token}", "IN_GROUP"),
        (f"role_{token}", f"resource_z_{token}", "CAN_ACCESS"),
        (f"group_two_{token}", f"resource_a_{token}", "CAN_ACCESS"),
        (f"group_three_{token}", f"resource_a_{token}", "CAN_ACCESS"),
        (f"unrelated_{token}", f"resource_hidden_{token}", "CAN_ACCESS"),
        (f"unrelated_{token}", f"group_one_{token}", "IN_GROUP"),
    ]

    second_edges = [
        (user, f"new_group_{token}", "IN_GROUP"),
        (f"new_group_{token}", f"new_role_{token}", "HAS_ROLE"),
        (f"new_role_{token}", f"new_tail_{token}", "IN_GROUP"),
        (f"new_tail_{token}", f"new_group_{token}", "IN_GROUP"),
        (f"new_tail_{token}", f"resource_changed_{token}", "CAN_ACCESS"),
        (f"detached_{token}", f"resource_decoy_{token}", "CAN_ACCESS"),
    ]

    try:
        run_case(first_edges)
        run_case(second_edges)
    finally:
        edges_path.write_bytes(original_edges)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
