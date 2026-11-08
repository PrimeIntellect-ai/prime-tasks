#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import stat
import subprocess
import uuid
from pathlib import Path

AUDIT = Path("/home/user/audit.go")
GRAPH = Path("/home/user/graph_data.jsonl")
OUTPUT = Path("/home/user/flagged_users.txt")
BINARY = Path("/tmp/audit_submission")


def parse_graph(data):
    nodes = {}
    edges = []
    for raw_line in data.decode().splitlines():
        if not raw_line.strip():
            continue
        obj = json.loads(raw_line)
        if obj.get("type") == "node":
            nodes[obj["id"]] = obj
        elif obj.get("type") == "edge":
            edges.append(obj)
    return nodes, edges


def legacy_expected(data):
    # Preserve the original verifier's assertion for the supplied graph.
    nodes, edges = parse_graph(data)
    target_res_ids = [
        n["id"] for n in nodes.values()
        if n.get("label") == "Resource" and n.get("name") == "customer_pii_db"
    ]
    assert len(target_res_ids) == 1, "Could not uniquely identify the 'customer_pii_db' resource in the graph."

    reverse_adj = {node_id: [] for node_id in nodes}
    for edge in edges:
        if edge["to"] in reverse_adj:
            reverse_adj[edge["to"]].append((edge["from"], edge["relation"]))

    reachable_users = []
    visited = set()

    def dfs(current_id):
        if current_id in visited:
            return
        visited.add(current_id)
        node = nodes.get(current_id)
        if node and node.get("label") == "User":
            reachable_users.append(node)
        for neighbor, relation in reverse_adj.get(current_id, []):
            if relation in ("CAN_ACCESS", "INHERITS", "HAS_ROLE"):
                dfs(neighbor)

    dfs(target_res_ids[0])
    reachable_users.sort(key=lambda user: user["id"])
    return [f"{user['id']},{user['name']}" for user in reachable_users]


def semantic_expected(data):
    nodes, edges = parse_graph(data)
    targets = {
        node_id for node_id, node in nodes.items()
        if node.get("label") == "Resource" and node.get("name") == "customer_pii_db"
    }
    assert len(targets) == 1
    target = next(iter(targets))

    assigned = {}
    inherited = {}
    accessible = set()
    for edge in edges:
        source = edge.get("from")
        destination = edge.get("to")
        relation = edge.get("relation")
        source_node = nodes.get(source, {})
        destination_node = nodes.get(destination, {})
        if relation == "HAS_ROLE" and source_node.get("label") == "User" and destination_node.get("label") == "Role":
            assigned.setdefault(source, set()).add(destination)
        elif relation == "INHERITS" and source_node.get("label") == "Role" and destination_node.get("label") == "Role":
            inherited.setdefault(source, set()).add(destination)
        elif relation == "CAN_ACCESS" and source_node.get("label") == "Role" and destination == target:
            accessible.add(source)

    result = []
    for user_id, user in nodes.items():
        if user.get("label") != "User":
            continue
        stack = list(assigned.get(user_id, ()))
        visited = set()
        has_access = False
        while stack:
            role = stack.pop()
            if role in visited:
                continue
            visited.add(role)
            if role in accessible:
                has_access = True
                break
            stack.extend(inherited.get(role, ()))
        if has_access:
            result.append((user_id, user["name"]))
    result.sort(key=lambda item: item[0])
    return [f"{user_id},{name}" for user_id, name in result]


def read_output():
    assert OUTPUT.exists(), f"Output file {OUTPUT} does not exist. The Go program must generate this file."
    with OUTPUT.open() as handle:
        return [line.strip() for line in handle if line.strip()]


def run_program(expected, graph_bytes):
    GRAPH.write_bytes(graph_bytes)
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()

    completed = subprocess.run(
        [str(BINARY)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f"Compiled audit program exited with status {completed.returncode}.\n"
        f"stdout: {completed.stdout}\nstderr: {completed.stderr}"
    )
    assert GRAPH.read_bytes() == graph_bytes, "The audit program must parse, not modify, graph_data.jsonl."
    actual = read_output()
    assert actual == expected, (
        f"The contents of {OUTPUT} do not match the expected output.\n"
        f"Expected: {expected}\nGot: {actual}"
    )


def make_fixture(depth):
    token = uuid.uuid4().hex[:10]
    def ident(prefix):
        return f"{prefix}_{token}_{uuid.uuid4().hex[:8]}"

    target = ident("res_target")
    other_resource = ident("res_other")
    direct_role = ident("role_direct")
    chain = [ident("role_chain") for _ in range(depth)]
    cycle_a = ident("role_cycle_a")
    cycle_b = ident("role_cycle_b")
    denied_role = ident("role_denied")
    reverse_role = ident("role_reverse")

    direct_user = ident("user")
    deep_user = ident("user")
    cycle_user = ident("user")
    denied_user = ident("user")
    wrong_relation_user = ident("user")
    reverse_user = ident("user")

    nodes = [
        {"type": "node", "id": target, "label": "Resource", "name": "customer_pii_db"},
        {"type": "node", "id": other_resource, "label": "Resource", "name": "public_data"},
        {"type": "node", "id": direct_role, "label": "Role", "name": "Direct"},
        {"type": "node", "id": cycle_a, "label": "Role", "name": "CycleA"},
        {"type": "node", "id": cycle_b, "label": "Role", "name": "CycleB"},
        {"type": "node", "id": denied_role, "label": "Role", "name": "Denied"},
        {"type": "node", "id": reverse_role, "label": "Role", "name": "Reverse"},
        {"type": "node", "id": direct_user, "label": "User", "name": f"Direct_{token}"},
        {"type": "node", "id": deep_user, "label": "User", "name": f"Deep_{token}"},
        {"type": "node", "id": cycle_user, "label": "User", "name": f"Cycle_{token}"},
        {"type": "node", "id": denied_user, "label": "User", "name": f"Denied_{token}"},
        {"type": "node", "id": wrong_relation_user, "label": "User", "name": f"WrongRelation_{token}"},
        {"type": "node", "id": reverse_user, "label": "User", "name": f"Reverse_{token}"},
    ]
    nodes.extend(
        {"type": "node", "id": role, "label": "Role", "name": f"Nested{index}"}
        for index, role in enumerate(chain)
    )

    edges = [
        {"type": "edge", "from": direct_user, "to": direct_role, "relation": "HAS_ROLE"},
        {"type": "edge", "from": direct_role, "to": target, "relation": "CAN_ACCESS"},
        {"type": "edge", "from": deep_user, "to": chain[0], "relation": "HAS_ROLE"},
        {"type": "edge", "from": chain[-1], "to": target, "relation": "CAN_ACCESS"},
        {"type": "edge", "from": cycle_user, "to": cycle_a, "relation": "HAS_ROLE"},
        {"type": "edge", "from": cycle_a, "to": cycle_b, "relation": "INHERITS"},
        {"type": "edge", "from": cycle_b, "to": cycle_a, "relation": "INHERITS"},
        {"type": "edge", "from": cycle_b, "to": target, "relation": "CAN_ACCESS"},
        {"type": "edge", "from": denied_user, "to": denied_role, "relation": "HAS_ROLE"},
        {"type": "edge", "from": denied_role, "to": other_resource, "relation": "CAN_ACCESS"},
        {"type": "edge", "from": wrong_relation_user, "to": direct_role, "relation": "INHERITS"},
        {"type": "edge", "from": reverse_user, "to": reverse_role, "relation": "HAS_ROLE"},
        {"type": "edge", "from": target, "to": reverse_role, "relation": "CAN_ACCESS"},
    ]
    edges.extend(
        {"type": "edge", "from": chain[index], "to": chain[index + 1], "relation": "INHERITS"}
        for index in range(len(chain) - 1)
    )

    records = nodes + edges
    random.SystemRandom().shuffle(records)
    return ("\n".join(json.dumps(record) for record in records) + "\n").encode()


def test_audit_program_and_output():
    assert AUDIT.exists(), f"Required Go source file {AUDIT} does not exist."
    assert stat.S_ISREG(AUDIT.lstat().st_mode), f"{AUDIT} must be a regular Go source file."
    assert GRAPH.exists(), f"Input file {GRAPH} is missing."

    build = subprocess.run(
        ["go", "build", "-o", str(BINARY), str(AUDIT)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"audit.go does not compile:\n{build.stdout}\n{build.stderr}"
    assert BINARY.is_file(), "Compiling audit.go did not produce an executable."

    original_graph = GRAPH.read_bytes()
    try:
        original_expected = legacy_expected(original_graph)
        run_program(original_expected, original_graph)

        for depth in (4, 9):
            fixture = make_fixture(depth)
            expected = semantic_expected(fixture)
            run_program(expected, fixture)
    finally:
        GRAPH.write_bytes(original_graph)
        try:
            if BINARY.exists():
                if OUTPUT.exists() or OUTPUT.is_symlink():
                    OUTPUT.unlink()
                subprocess.run([str(BINARY)], cwd="/home/user", timeout=20, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
