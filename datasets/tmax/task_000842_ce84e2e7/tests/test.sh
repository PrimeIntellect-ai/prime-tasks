#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import string
import subprocess

import pytest

HOME = "/home/user"
PROGRAM = os.path.join(HOME, "graph_processor")
REBUILT = "/tmp/graph_processor_rebuilt"


def write_original_fixture():
    with open(os.path.join(HOME, "nodes.txt"), "w") as f:
        f.write('1|User|{"status":"active","age":30}\n')
        f.write('2|User|{"status":"inactive","age":25}\n')
        f.write('3|Group|{"status":"active","name":"Admins"}\n')
        f.write('4|Group|{"status":"active","name":"Users"}\n')
        f.write('5|Resource|{"status":"active","type":"Server"}\n')
        f.write('6|Resource|{"status":"archived","type":"Database"}\n')
        f.write('7|User|{"status":"active","age":45}\n')

    with open(os.path.join(HOME, "edges.txt"), "w") as f:
        f.write('1|3|MEMBER_OF|15\n')
        f.write('1|4|MEMBER_OF|5\n')
        f.write('2|4|MEMBER_OF|20\n')
        f.write('3|4|PARENT_OF|50\n')
        f.write('3|5|HAS_ACCESS|10\n')
        f.write('4|5|HAS_ACCESS|8\n')
        f.write('7|3|MEMBER_OF|12\n')
        f.write('7|6|HAS_ACCESS|25\n')


def run_program(path):
    result = subprocess.run(
        [path], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"{path} exited with {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_cjson_files_exist():
    assert os.path.isfile("/home/user/cJSON.h"), "cJSON.h is missing from /home/user/"
    assert os.path.isfile("/home/user/cJSON.c"), "cJSON.c is missing from /home/user/"


def test_c_program_files_exist():
    assert os.path.isfile("/home/user/graph_processor.c"), "graph_processor.c is missing"
    assert os.path.isfile(PROGRAM), "graph_processor executable is missing"
    assert os.access(PROGRAM, os.X_OK), "graph_processor is not executable"
    with open(PROGRAM, "rb") as f:
        assert f.read(4) == b"\x7fELF", "graph_processor is not a compiled ELF executable"


def test_execute_program_on_original_fixture():
    write_original_fixture()
    for output in ("active_subgraph.cypher", "edge_aggregation.json"):
        path = os.path.join(HOME, output)
        if os.path.exists(path):
            os.remove(path)
    run_program(PROGRAM)


def test_active_subgraph_cypher():
    cypher_path = "/home/user/active_subgraph.cypher"
    assert os.path.isfile(cypher_path), f"{cypher_path} is missing"

    with open(cypher_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        'CREATE (n1:User {id: "1", status: "active"});',
        'CREATE (n3:Group {id: "3", status: "active"});',
        'CREATE (n4:Group {id: "4", status: "active"});',
        'CREATE (n5:Resource {id: "5", status: "active"});',
        'CREATE (n7:User {id: "7", status: "active"});',
        'MATCH (a {id: "1"}), (b {id: "3"}) CREATE (a)-[:MEMBER_OF {weight: 15}]->(b);',
        'MATCH (a {id: "3"}), (b {id: "4"}) CREATE (a)-[:PARENT_OF {weight: 50}]->(b);',
        'MATCH (a {id: "3"}), (b {id: "5"}) CREATE (a)-[:HAS_ACCESS {weight: 10}]->(b);',
        'MATCH (a {id: "7"}), (b {id: "3"}) CREATE (a)-[:MEMBER_OF {weight: 12}]->(b);'
    ]

    assert lines == expected_lines, "The contents of active_subgraph.cypher do not match the expected output exactly."


def test_edge_aggregation_json():
    json_path = "/home/user/edge_aggregation.json"
    assert os.path.isfile(json_path), f"{json_path} is missing"

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Could not parse JSON from {json_path}")

    expected_data = {
        "MEMBER_OF": 52,
        "PARENT_OF": 50,
        "HAS_ACCESS": 43
    }

    assert data == expected_data, "The contents of edge_aggregation.json do not match the expected aggregation."


def make_dynamic_fixture():
    rng = random.SystemRandom()
    ids = rng.sample(range(100, 950), 7)
    suffix = ''.join(rng.choice(string.ascii_uppercase) for _ in range(7))
    rel_a = "LINK_" + suffix
    rel_b = "OWNS_" + suffix
    rel_c = "USES_" + suffix

    nodes = [
        (ids[0], "User", {"age": rng.randrange(20, 70), "status": "active"}),
        (ids[1], "Group", {"status": "inactive", "name": "Dormant"}),
        (ids[2], "Resource", {"name": "Primary", "status": "active"}),
        (ids[3], "Device", {"status": "active", "enabled": True}),
        (ids[4], "User", {"status": "archived"}),
        (ids[5], "Group", {"status": "Active"}),
        (ids[6], "Resource", {"count": 3, "status": "active"}),
    ]

    bump = rng.randrange(1, 20)
    edges = [
        (ids[0], ids[2], rel_a, 10 + bump),
        (ids[0], ids[3], rel_b, 9),
        (ids[2], ids[3], rel_b, 25 + bump),
        (ids[3], ids[6], rel_c, 10),
        (ids[6], ids[0], rel_a, 18),
        (ids[1], ids[2], rel_a, 40),
        (ids[2], ids[4], rel_c, 31),
        (ids[5], ids[6], rel_b, 22),
    ]
    rng.shuffle(nodes)
    rng.shuffle(edges)
    return nodes, edges


def expected_outputs(nodes, edges):
    active = {
        node_id for node_id, _node_type, props in nodes
        if props.get("status") == "active"
    }
    node_types = {node_id: node_type for node_id, node_type, _props in nodes}

    cypher = [
        f'CREATE (n{node_id}:{node_types[node_id]} {{id: "{node_id}", status: "active"}});'
        for node_id in sorted(active)
    ]
    projected_edges = sorted(
        (src, tgt, rel, weight)
        for src, tgt, rel, weight in edges
        if src in active and tgt in active and weight >= 10
    )
    cypher.extend(
        f'MATCH (a {{id: "{src}"}}), (b {{id: "{tgt}"}}) CREATE (a)-[:{rel} {{weight: {weight}}}]->(b);'
        for src, tgt, rel, weight in projected_edges
    )

    aggregation = {}
    for _src, _tgt, rel, weight in edges:
        aggregation[rel] = aggregation.get(rel, 0) + weight
    return cypher, aggregation


def write_dynamic_fixture(nodes, edges):
    with open(os.path.join(HOME, "nodes.txt"), "w") as f:
        for node_id, node_type, props in nodes:
            encoded = json.dumps(props, separators=(",", ":"))
            f.write(f"{node_id}|{node_type}|{encoded}\n")
    with open(os.path.join(HOME, "edges.txt"), "w") as f:
        for src, tgt, rel, weight in edges:
            f.write(f"{src}|{tgt}|{rel}|{weight}\n")


def assert_dynamic_result(binary, nodes, edges):
    write_dynamic_fixture(nodes, edges)
    for output in ("active_subgraph.cypher", "edge_aggregation.json"):
        path = os.path.join(HOME, output)
        if os.path.exists(path):
            os.remove(path)

    run_program(binary)
    expected_cypher, expected_aggregation = expected_outputs(nodes, edges)

    cypher_path = os.path.join(HOME, "active_subgraph.cypher")
    assert os.path.isfile(cypher_path), "program did not generate active_subgraph.cypher"
    with open(cypher_path) as f:
        actual_cypher = [line.strip() for line in f if line.strip()]
    assert actual_cypher == expected_cypher

    aggregation_path = os.path.join(HOME, "edge_aggregation.json")
    assert os.path.isfile(aggregation_path), "program did not generate edge_aggregation.json"
    with open(aggregation_path) as f:
        actual_aggregation = json.load(f)
    assert actual_aggregation == expected_aggregation


def test_executable_and_source_on_dynamic_fixture():
    nodes, edges = make_dynamic_fixture()
    assert_dynamic_result(PROGRAM, nodes, edges)

    if os.path.exists(REBUILT):
        os.remove(REBUILT)
    primary = subprocess.run(
        ["gcc", "graph_processor.c", "cJSON.c", "-o", REBUILT, "-lm"],
        cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    if primary.returncode != 0:
        if os.path.exists(REBUILT):
            os.remove(REBUILT)
        fallback = subprocess.run(
            ["gcc", "graph_processor.c", "-o", REBUILT, "-lm"],
            cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert fallback.returncode == 0, (
            "graph_processor.c could not be compiled with the supplied cJSON source\n"
            f"primary stderr:\n{primary.stderr}\n"
            f"fallback stderr:\n{fallback.stderr}"
        )

    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)
    assert_dynamic_result(REBUILT, nodes, edges)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
