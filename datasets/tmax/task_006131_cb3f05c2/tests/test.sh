#!/bin/bash
set -e
mkdir -p /logs/verifier

backup_dir=$(mktemp -d)
cp /home/user/graph_nodes.csv "$backup_dir/graph_nodes.csv"
cp /home/user/graph_edges.csv "$backup_dir/graph_edges.csv"
if [ -f /home/user/top_patterns.json ]; then
    cp /home/user/top_patterns.json "$backup_dir/top_patterns.json"
    had_output=1
else
    had_output=0
fi
cleanup() {
    cp "$backup_dir/graph_nodes.csv" /home/user/graph_nodes.csv 2>/dev/null || true
    cp "$backup_dir/graph_edges.csv" /home/user/graph_edges.csv 2>/dev/null || true
    if [ "$had_output" = 1 ]; then
        cp "$backup_dir/top_patterns.json" /home/user/top_patterns.json 2>/dev/null || true
    else
        rm -f /home/user/top_patterns.json
    fi
    rm -rf "$backup_dir"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess

PROGRAM = "/home/user/extract_patterns.go"
NODES = "/home/user/graph_nodes.csv"
EDGES = "/home/user/graph_edges.csv"
OUTPUT = "/home/user/top_patterns.json"


def run_program():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ["go", "run", PROGRAM],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Go program failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(OUTPUT), f"The output file {OUTPUT} is missing."
    assert os.path.isfile(OUTPUT), f"The path {OUTPUT} is not a file."


def load_output():
    with open(OUTPUT, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"The file {OUTPUT} does not contain valid JSON: {exc}")


def assert_records(actual, expected):
    assert isinstance(actual, list), f"The JSON root should be a list, but got {type(actual).__name__}."
    assert len(actual) == 3, f"Expected exactly 3 items in the JSON array, but got {len(actual)}."

    for i, (item, wanted) in enumerate(zip(actual, expected)):
        assert isinstance(item, dict), f"Item at index {i} is not a JSON object."
        expected_keys = set(wanted.keys())
        actual_keys = set(item.keys())
        assert actual_keys == expected_keys, f"Item at index {i} has keys {actual_keys}, expected {expected_keys}."
        assert item["bot_id"] == wanted["bot_id"], f"Item at index {i} has bot_id {item['bot_id']}, expected {wanted['bot_id']}."
        assert item["user_id"] == wanted["user_id"], f"Item at index {i} has user_id {item['user_id']}, expected {wanted['user_id']}."
        assert item["post_id"] == wanted["post_id"], f"Item at index {i} has post_id {item['post_id']}, expected {wanted['post_id']}."
        actual_weight = item["total_weight"]
        expected_weight = wanted["total_weight"]
        assert isinstance(actual_weight, (int, float)) and not isinstance(actual_weight, bool), f"Item at index {i} total_weight is not a number."
        assert abs(actual_weight - expected_weight) < 1e-6, f"Item at index {i} has total_weight {actual_weight}, expected {expected_weight}."


def derive_expected():
    node_types = {}
    with open(NODES, newline="") as f:
        for row in csv.DictReader(f):
            node_types[row["id"]] = row["type"]

    outgoing = {}
    with open(EDGES, newline="") as f:
        for row in csv.DictReader(f):
            outgoing.setdefault(row["source"], []).append(row)

    results = []
    for bot_id, node_type in node_types.items():
        if node_type != "Bot":
            continue
        for follows in outgoing.get(bot_id, []):
            user_id = follows["target"]
            if follows["relation"] != "follows" or node_types.get(user_id) != "User":
                continue
            for likes in outgoing.get(user_id, []):
                post_id = likes["target"]
                if likes["relation"] != "likes" or node_types.get(post_id) != "Post":
                    continue
                results.append({
                    "bot_id": bot_id,
                    "user_id": user_id,
                    "post_id": post_id,
                    "total_weight": float(follows["weight"]) + float(likes["weight"]),
                })
    results.sort(key=lambda r: (-r["total_weight"], r["bot_id"], r["user_id"]))
    return results[:3]


def test_go_program_exists_and_original_output_content():
    assert os.path.exists(PROGRAM), f"The Go program {PROGRAM} is missing."
    assert os.path.isfile(PROGRAM), f"The path {PROGRAM} is not a file."

    run_program()
    data = load_output()
    expected_data = [
        {"bot_id": "n4", "user_id": "n5", "post_id": "n6", "total_weight": 1.6},
        {"bot_id": "n7", "user_id": "n8", "post_id": "n6", "total_weight": 1.4},
        {"bot_id": "n1", "user_id": "n2", "post_id": "n3", "total_weight": 1.3},
    ]
    assert_records(data, expected_data)


def test_program_traverses_changed_graph_and_sorts_and_paginates():
    prefix = secrets.token_hex(6) + "_"
    ids = {name: prefix + name for name in (
        "bot_a", "bot_b", "bot_c", "bot_d",
        "user_a", "user_b", "user_c",
        "post_a", "post_b", "post_c", "other",
    )}

    nodes = [
        (ids["bot_a"], "Bot"), (ids["bot_b"], "Bot"),
        (ids["bot_c"], "Bot"), (ids["bot_d"], "Bot"),
        (ids["user_a"], "User"), (ids["user_b"], "User"),
        (ids["user_c"], "User"), (ids["post_a"], "Post"),
        (ids["post_b"], "Post"), (ids["post_c"], "Post"),
        (ids["other"], "User"),
    ]
    edges = [
        (ids["bot_a"], ids["user_a"], "follows", "0.8"),
        (ids["user_a"], ids["post_a"], "likes", "0.7"),
        (ids["bot_b"], ids["user_b"], "follows", "0.9"),
        (ids["user_b"], ids["post_b"], "likes", "0.6"),
        (ids["bot_c"], ids["user_c"], "follows", "0.4"),
        (ids["user_c"], ids["post_c"], "likes", "0.95"),
        (ids["bot_d"], ids["user_a"], "follows", "0.2"),
        (ids["bot_a"], ids["user_b"], "follows", "0.1"),
        (ids["user_a"], ids["post_b"], "likes", "0.05"),
        (ids["bot_b"], ids["post_c"], "follows", "9.0"),
        (ids["bot_c"], ids["user_a"], "mentions", "9.0"),
        (ids["user_c"], ids["post_a"], "shares", "9.0"),
        (ids["other"], ids["post_c"], "likes", "9.0"),
    ]

    with open(NODES, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "type"])
        writer.writerows(nodes)
    with open(EDGES, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["source", "target", "relation", "weight"])
        writer.writerows(edges)

    expected = derive_expected()
    run_program()
    assert_records(load_output(), expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
