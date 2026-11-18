#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import secrets
import subprocess

SCRIPT = "/home/user/analyze_plan.py"
PLAN = "/home/user/query_plan.json"
SOURCES = "/home/user/sources.csv"
OUTPUT = "/home/user/critical_path_types.txt"

CANONICAL_PLAN = {
    "nodes": [
        {"id": "stage_1", "source_id": "db_alpha", "time_ms": 150},
        {"id": "stage_2", "source_id": "db_beta", "time_ms": 320},
        {"id": "stage_3", "source_id": "db_gamma", "time_ms": 45},
        {"id": "stage_4", "source_id": "db_delta", "time_ms": 600},
        {"id": "stage_5", "source_id": "db_epsilon", "time_ms": 800},
        {"id": "stage_6", "source_id": "db_alpha", "time_ms": 120},
    ],
    "edges": [
        {"from": "stage_4", "to": "stage_2"},
        {"from": "stage_5", "to": "stage_3"},
        {"from": "stage_2", "to": "stage_1"},
        {"from": "stage_3", "to": "stage_1"},
        {"from": "stage_6", "to": "stage_4"},
    ],
}

CANONICAL_SOURCES = [
    ("db_alpha", "relational"),
    ("db_beta", "document"),
    ("db_gamma", "graph"),
    ("db_delta", "relational"),
    ("db_epsilon", "document"),
]


def write_inputs(plan, sources):
    with open(PLAN, "w") as f:
        json.dump(plan, f)
    with open(SOURCES, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["source_id", "type"])
        writer.writerows(sources)


def derive_expected(plan, sources):
    nodes = {node["id"]: node for node in plan["nodes"]}
    outgoing = {node_id: [] for node_id in nodes}
    indegree = {node_id: 0 for node_id in nodes}
    for edge in plan["edges"]:
        outgoing[edge["from"]].append(edge["to"])
        indegree[edge["to"]] += 1

    best = None

    def visit(node_id, path, total):
        nonlocal best
        path = path + [node_id]
        total += nodes[node_id]["time_ms"]
        if not outgoing[node_id]:
            candidate = (total, path)
            if best is None or candidate[0] > best[0]:
                best = candidate
            return
        for parent in outgoing[node_id]:
            visit(parent, path, total)

    for node_id, degree in indegree.items():
        if degree == 0:
            visit(node_id, [], 0)

    assert best is not None
    source_types = dict(sources)
    return ",".join(source_types[nodes[node_id]["source_id"]] for node_id in best[1])


def run_script():
    if os.path.lexists(OUTPUT):
        if os.path.isdir(OUTPUT) and not os.path.islink(OUTPUT):
            raise AssertionError(f"The output path {OUTPUT} is a directory")
        os.unlink(OUTPUT)
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{SCRIPT} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(OUTPUT), f"The output file {OUTPUT} does not exist."
    assert os.path.isfile(OUTPUT), f"The path {OUTPUT} is not a file."
    with open(OUTPUT, "r") as f:
        return f.read().strip()


def randomized_fixture():
    token = secrets.token_hex(6)
    node_ids = [f"node_{token}_{i}" for i in range(9)]
    source_ids = [f"source_{token}_{i}" for i in range(9)]
    types = [secrets.choice(["relational", "document", "graph"]) for _ in range(9)]
    weights = [1 << i for i in range(9)]
    secrets.SystemRandom().shuffle(weights)

    nodes = [
        {"id": node_ids[i], "source_id": source_ids[i], "time_ms": weights[i]}
        for i in range(9)
    ]
    edge_indexes = [
        (0, 3), (1, 3), (2, 4), (3, 5), (4, 5),
        (6, 7), (5, 8), (7, 8),
    ]
    edges = [{"from": node_ids[a], "to": node_ids[b]} for a, b in edge_indexes]
    return {"nodes": nodes, "edges": edges}, list(zip(source_ids, types))


def test_critical_path_output():
    assert os.path.exists(SCRIPT), f"The required script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"The path {SCRIPT} is not a file."
    with open(SCRIPT, "r") as f:
        ast.parse(f.read(), filename=SCRIPT)

    # Preserve the original exact-output assertion using the supplied plan.
    write_inputs(CANONICAL_PLAN, CANONICAL_SOURCES)
    content = run_script()
    expected_content = "relational,relational,document,relational"
    assert content == expected_content, (
        f"The content of {OUTPUT} is incorrect.\n"
        f"Expected: '{expected_content}'\n"
        f"Found: '{content}'"
    )

    # Exercise the submitted script on unpredictable valid DAGs and derive each
    # expected answer independently from the generated JSON and CSV data.
    for _ in range(3):
        plan, sources = randomized_fixture()
        expected = derive_expected(plan, sources)
        write_inputs(plan, sources)
        content = run_script()
        assert content == expected, (
            f"Incorrect critical path for a generated plan.\n"
            f"Expected: '{expected}'\nFound: '{content}'"
        )

    # Leave the supplied inputs and their required output in the expected state.
    write_inputs(CANONICAL_PLAN, CANONICAL_SOURCES)
    assert run_script() == expected_content
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
