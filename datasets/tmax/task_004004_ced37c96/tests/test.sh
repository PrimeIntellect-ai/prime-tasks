#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/query_graph.py"
NODES_PATH = "/home/user/graph_data/nodes.csv"
EDGES_PATH = "/home/user/graph_data/edges.csv"


def compute_expected(action, min_weight, sort_order, limit, offset):
    nodes = {}
    with open(NODES_PATH, "r", newline="") as f:
        for row in csv.DictReader(f):
            nodes[row["node_id"]] = {
                "label": row["label"],
                "weight": int(row["weight"]),
            }

    with open(EDGES_PATH, "r", newline="") as f:
        edges = list(csv.DictReader(f))

    paths = []
    for e1 in edges:
        if e1["rel_type"] != action:
            continue
        u_id = e1["source_id"]
        i_id = e1["target_id"]
        if u_id not in nodes or nodes[u_id]["label"] != "User":
            continue
        if i_id not in nodes or nodes[i_id]["label"] != "Item":
            continue
        if nodes[i_id]["weight"] < min_weight:
            continue

        for e2 in edges:
            if e2["source_id"] != i_id or e2["rel_type"] != "BELONGS_TO":
                continue
            c_id = e2["target_id"]
            if c_id in nodes and nodes[c_id]["label"] == "Category":
                paths.append({
                    "user_id": u_id,
                    "item_id": i_id,
                    "category_id": c_id,
                    "path_score": nodes[u_id]["weight"] + nodes[i_id]["weight"],
                })

    if sort_order == "asc":
        paths.sort(key=lambda x: (x["path_score"], x["user_id"]))
    else:
        paths.sort(key=lambda x: (-x["path_score"], x["user_id"]))
    return paths[offset:offset + limit]


def run_and_check(action, min_weight, sort_order, limit, offset, output_path):
    if os.path.exists(output_path):
        os.remove(output_path)

    cmd = [
        "python3", SCRIPT_PATH,
        "--action", action,
        "--min-weight", str(min_weight),
        "--sort-order", sort_order,
        "--limit", str(limit),
        "--offset", str(offset),
        "--output", output_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Script failed with error: {result.stderr}\nOutput: {result.stdout}"
    )
    assert os.path.isfile(output_path), f"Output file {output_path} was not created by the script."

    with open(output_path, "r") as f:
        try:
            output_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Output file is not valid JSON.")

    expected_data = compute_expected(action, min_weight, sort_order, limit, offset)
    assert output_data == expected_data, (
        f"Output JSON does not match expected data for action={action}, "
        f"min_weight={min_weight}, sort_order={sort_order}, limit={limit}, offset={offset}.\n"
        f"Expected: {json.dumps(expected_data, indent=2)}\n"
        f"Got: {json.dumps(output_data, indent=2)}"
    )


def test_query_graph_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_original_execution_and_logic():
    # Preserve the original verifier's fixed assertion.
    run_and_check("PURCHASED", 40, "desc", 2, 1, "/home/user/test_output.json")


def test_parameterized_behavior_on_fresh_graph_data():
    with open(NODES_PATH, "r") as f:
        original_nodes = f.read()
    with open(EDGES_PATH, "r") as f:
        original_edges = f.read()

    token = secrets.token_hex(6)
    action_a = "ACTION_A_" + token
    action_b = "ACTION_B_" + token
    users = [f"U_{token}_{x}" for x in ("z", "a", "m", "q", "b")]
    items = [f"I_{token}_{i}" for i in range(6)]
    cats = [f"C_{token}_{i}" for i in range(3)]

    # The first two paths tie at 100, forcing the user_id tie-break rule.
    node_rows = [
        [users[0], "User", 17],
        [users[1], "User", 29],
        [users[2], "User", 11],
        [users[3], "User", 37],
        [users[4], "User", 23],
        [items[0], "Item", 83],
        [items[1], "Item", 71],
        [items[2], "Item", 44],
        [items[3], "Item", 63],
        [items[4], "Item", 28],
        [items[5], "Item", 52],
        [cats[0], "Category", 0],
        [cats[1], "Category", 0],
        [cats[2], "Category", 0],
        [f"NOTCAT_{token}", "Other", 0],
        [f"NOTUSER_{token}", "Other", 50],
    ]
    edge_rows = [
        [users[0], items[0], action_a],
        [users[1], items[1], action_a],
        [users[2], items[2], action_a],
        [users[3], items[3], action_a],
        [users[4], items[4], action_a],
        [users[0], items[5], action_b],
        [users[2], items[1], action_b],
        [items[0], cats[0], "BELONGS_TO"],
        [items[1], cats[1], "BELONGS_TO"],
        [items[1], cats[2], "BELONGS_TO"],
        [items[2], cats[0], "BELONGS_TO"],
        [items[3], cats[2], "BELONGS_TO"],
        [items[4], cats[1], "BELONGS_TO"],
        [items[5], cats[0], "BELONGS_TO"],
        # Noise that must not form valid paths.
        [f"NOTUSER_{token}", items[0], action_a],
        [users[0], cats[0], action_a],
        [items[0], f"NOTCAT_{token}", "BELONGS_TO"],
        [items[2], cats[1], "belongs_to"],
        [cats[0], items[0], "BELONGS_TO"],
    ]

    try:
        with open(NODES_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["node_id", "label", "weight"])
            writer.writerows(node_rows)
        with open(EDGES_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["source_id", "target_id", "rel_type"])
            writer.writerows(edge_rows)

        cases = [
            (action_a, 0, "asc", 20, 0),
            (action_a, 44, "desc", 3, 1),
            (action_a, 71, "asc", 2, 0),
            (action_b, 0, "desc", 10, 0),
            (action_b, 60, "asc", 5, 0),
            ("MISSING_" + token, 0, "desc", 4, 0),
        ]
        for index, args in enumerate(cases):
            run_and_check(*args, f"/tmp/query_graph_{token}_{index}.json")
    finally:
        with open(NODES_PATH, "w") as f:
            f.write(original_nodes)
        with open(EDGES_PATH, "w") as f:
            f.write(original_edges)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
