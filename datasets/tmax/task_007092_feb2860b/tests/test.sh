#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
from collections import defaultdict


def get_expected_data():
    raw_file = "/home/user/raw_events.json"
    assert os.path.isfile(raw_file), f"{raw_file} is missing."

    with open(raw_file, 'r') as f:
        events = json.load(f)

    counts = defaultdict(int)
    for event in events:
        if event.get("action") == "VIEWED":
            user = event.get("user_id")
            product = event.get("product_id")
            if user and product:
                counts[(user, product)] += 1

    expected_json = []
    for (user, product) in sorted(counts.keys()):
        expected_json.append({
            "user": user,
            "product": product,
            "weight": counts[(user, product)]
        })

    expected_cypher = []
    for item in expected_json:
        u = item['user']
        p = item['product']
        w = item['weight']
        line = f"MERGE (u:User {{id: '{u}'}}) MERGE (p:Product {{id: '{p}'}}) MERGE (u)-[:VIEWED {{weight: {w}}}]->(p);"
        expected_cypher.append(line)

    return expected_json, expected_cypher


def test_etl_script_exists_and_executable():
    script_path = "/home/user/etl.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_aggregated_views_json():
    output_file = "/home/user/aggregated_views.json"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."

    with open(output_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {output_file} is not valid JSON."

    expected_json, _ = get_expected_data()

    assert isinstance(data, list), f"Data in {output_file} must be a JSON array."
    assert len(data) == len(expected_json), f"Expected {len(expected_json)} elements, found {len(data)}."
    assert data == expected_json, f"Data in {output_file} does not match expected aggregated views or is not sorted properly."


def test_graph_import_cypher():
    output_file = "/home/user/graph_import.cypher"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."

    _, expected_cypher = get_expected_data()

    with open(output_file, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_cypher), f"Expected {len(expected_cypher)} lines in {output_file}, found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_cypher)):
        assert actual == expected, f"Line {i+1} in {output_file} does not match expected.\nExpected: {expected}\nActual: {actual}"
TEST_EOF

run_verification() {
    test -f /home/user/etl.sh || return 1
    test -x /home/user/etl.sh || return 1

    python3 - << 'DATA_EOF' || return 1
import json
import secrets

t = secrets.token_hex(8)
ua, ub, uc = f"alpha_{t}", f"beta_{t}", f"gamma_{t}"
pa, pb, pc = f"item_a_{t}", f"item_b_{t}", f"item_c_{t}"
events = [
    {"user_id": ua, "action": "VIEWED", "product_id": pa, "timestamp": "2026-01-01T00:00:00Z"},
    {"user_id": ua, "action": "PURCHASED", "product_id": pa, "timestamp": "2026-01-01T00:01:00Z"},
    {"user_id": ub, "action": "VIEWED", "product_id": pb, "timestamp": "2026-01-01T00:02:00Z"},
    {"user_id": ua, "action": "VIEWED", "product_id": pa, "timestamp": "2026-01-01T00:03:00Z"},
    {"user_id": uc, "action": "VIEWED", "product_id": pa, "timestamp": "2026-01-01T00:04:00Z"},
    {"user_id": ua, "action": "VIEWED", "product_id": pc, "timestamp": "2026-01-01T00:05:00Z"},
    {"user_id": ub, "action": "ADDED_TO_CART", "product_id": pc, "timestamp": "2026-01-01T00:06:00Z"},
    {"user_id": uc, "action": "VIEWED", "product_id": pa, "timestamp": "2026-01-01T00:07:00Z"}
]
with open("/home/user/raw_events.json", "w") as f:
    json.dump(events, f)
DATA_EOF

    rm -f /home/user/aggregated_views.json /home/user/graph_import.cypher || return 1
    (cd /home/user && timeout 30s /home/user/etl.sh) || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
}

if run_verification; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
