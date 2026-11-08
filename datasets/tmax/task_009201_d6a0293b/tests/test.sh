#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import subprocess

AUDIT_PATH = "/home/user/audit.py"
INVENTORY_PATH = "/home/user/inventory.json"
EDGES_PATH = "/home/user/access_edges.csv"
OUTPUT_PATH = "/home/user/violations.json"


def run_audit():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        ["python3", AUDIT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"audit.py failed with exit code {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert os.path.isfile(OUTPUT_PATH), "audit.py did not generate /home/user/violations.json"


def expected_for(inventory, edges):
    nodes = {node["id"]: node for node in inventory}
    adjacency = {node_id: [] for node_id in nodes}
    for source, target in edges:
        adjacency.setdefault(source, []).append(target)

    pii_databases = {
        node["id"]
        for node in inventory
        if node.get("type") == "Database" and node.get("contains_pii") is True
    }
    unauthorized_users = sorted(
        node["id"]
        for node in inventory
        if node.get("type") == "User" and node.get("authorized") is False
    )

    violations = []
    for user in unauthorized_users:
        seen = {user}
        stack = [user]
        while stack:
            current = stack.pop()
            for target in adjacency.get(current, []):
                if target not in seen:
                    seen.add(target)
                    stack.append(target)
        reachable = sorted(pii_databases.intersection(seen))
        if reachable:
            violations.append({"user": user, "reachable_pii_dbs": reachable})
    return {"violations": violations}


def assert_output(expected):
    with open(OUTPUT_PATH, "r") as f:
        raw_content = f.read()
    try:
        data = json.loads(raw_content)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"File {OUTPUT_PATH} is not valid JSON: {exc}")
    assert data == expected, f"The content of {OUTPUT_PATH} is incorrect. Got: {data}"
    expected_raw = json.dumps(data, indent=2)
    assert raw_content.strip() == expected_raw.strip(), (
        "The output JSON is not formatted with exactly 2 spaces of indentation "
        "or has unexpected formatting."
    )


def test_audit_script_exists_and_executes():
    assert os.path.isfile(AUDIT_PATH), f"File not found: {AUDIT_PATH}"
    run_audit()


def test_violations_file_exists():
    file_path = "/home/user/violations.json"
    assert os.path.isfile(file_path), f"File not found: {file_path}. The script did not generate the expected output file."


def test_violations_content():
    file_path = "/home/user/violations.json"
    assert os.path.isfile(file_path), "File not found."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {file_path} is not valid JSON."

    expected_data = {
        "violations": [
            {
                "user": "U2",
                "reachable_pii_dbs": ["DB1"]
            },
            {
                "user": "U3",
                "reachable_pii_dbs": ["DB1", "DB3"]
            }
        ]
    }

    assert data == expected_data, f"The content of {file_path} does not match the expected violations. Got: {data}"


def test_violations_formatting():
    file_path = "/home/user/violations.json"
    assert os.path.isfile(file_path), "File not found."

    with open(file_path, "r") as f:
        raw_content = f.read()

    with open(file_path, "r") as f:
        data = json.load(f)

    expected_raw = json.dumps(data, indent=2)
    assert raw_content.strip() == expected_raw.strip(), "The output JSON is not formatted with exactly 2 spaces of indentation or has unexpected formatting."


def test_audit_computes_from_changed_graph():
    with open(INVENTORY_PATH, "r") as f:
        original_inventory = f.read()
    with open(EDGES_PATH, "r") as f:
        original_edges = f.read()

    inventory = [
        {"id": "z-user", "type": "User", "authorized": False},
        {"id": "a-user", "type": "User", "authorized": False},
        {"id": "cleared", "type": "User", "authorized": True},
        {"id": "isolated", "type": "User", "authorized": False},
        {"id": "relay-a", "type": "Server"},
        {"id": "relay-b", "type": "Server"},
        {"id": "pii-z", "type": "Database", "contains_pii": True},
        {"id": "pii-a", "type": "Database", "contains_pii": True},
        {"id": "ordinary", "type": "Database", "contains_pii": False},
    ]
    edges = [
        ("z-user", "relay-a"),
        ("relay-a", "relay-b"),
        ("relay-b", "relay-a"),
        ("relay-a", "pii-z"),
        ("relay-b", "pii-a"),
        ("a-user", "pii-z"),
        ("isolated", "ordinary"),
        ("cleared", "pii-a"),
    ]

    try:
        with open(INVENTORY_PATH, "w") as f:
            json.dump(inventory, f, indent=2)
        with open(EDGES_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["source", "target"])
            writer.writerows(edges)

        run_audit()
        assert_output(expected_for(inventory, edges))
    finally:
        with open(INVENTORY_PATH, "w") as f:
            f.write(original_inventory)
        with open(EDGES_PATH, "w") as f:
            f.write(original_edges)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
