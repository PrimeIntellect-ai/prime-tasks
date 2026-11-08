#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import secrets
import shutil
import stat
import subprocess

import pytest

SCRIPT_PATH = "/home/user/etl_pipeline.py"
INPUT_PATH = "/home/user/data/edges.csv"
OUTPUT_DIR = "/home/user/output"
OUTPUT_PATH = "/home/user/output/nodes.jsonl"

with open(INPUT_PATH, "rb") as f:
    ORIGINAL_INPUT = f.read()


def get_edges():
    edges = []
    with open(INPUT_PATH, "r") as f:
        lines = f.read().strip().splitlines()
        for line in lines[1:]:
            u, v, w = line.split(",")
            edges.append((u, v, float(w)))
    return edges


def get_wcc(edges):
    adj = {}
    for u, v, _ in edges:
        if u not in adj:
            adj[u] = set()
        if v not in adj:
            adj[v] = set()
        adj[u].add(v)
        adj[v].add(u)

    visited = set()
    components = []
    for node in adj:
        if node not in visited:
            comp = set()
            queue = [node]
            visited.add(node)
            while queue:
                curr = queue.pop(0)
                comp.add(curr)
                for neighbor in adj[curr]:
                    if neighbor not in visited:
                        visited.add(neighbor)
                        queue.append(neighbor)
            components.append(comp)
    return components


def calculate_pagerank(edges, alpha=0.85, max_iter=100, tol=1.0e-6):
    nodes = set()
    out_weights = {}
    for u, v, w in edges:
        nodes.add(u)
        nodes.add(v)
        if u not in out_weights:
            out_weights[u] = 0.0
        out_weights[u] += w

    N = len(nodes)
    pr = {n: 1.0 / N for n in nodes}

    for _ in range(max_iter):
        new_pr = {n: 0.0 for n in nodes}
        dangling_sum = 0.0
        for n in nodes:
            if out_weights.get(n, 0) == 0:
                dangling_sum += pr[n]

        for n in nodes:
            new_pr[n] = (1.0 - alpha) / N + alpha * dangling_sum / N

        for u, v, w in edges:
            new_pr[v] += alpha * pr[u] * (w / out_weights[u])

        err = sum(abs(new_pr[n] - pr[n]) for n in nodes)
        pr = new_pr
        if err < tol:
            break
    return pr


def run_pipeline():
    if os.path.exists(OUTPUT_DIR):
        shutil.rmtree(OUTPUT_DIR)

    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        preexec_fn=demote,
    )
    assert result.returncode == 0, (
        "etl_pipeline.py failed when executed:\n"
        + result.stdout
        + result.stderr
    )


def validate_output(edges):
    components = get_wcc(edges)
    pr = calculate_pagerank(edges)

    expected_nodes = {}
    for comp in components:
        if len(comp) >= 3:
            for node in comp:
                expected_nodes[node] = {
                    "node_id": node,
                    "pagerank": pr[node],
                    "component_size": len(comp),
                }

    expected_sorted_keys = sorted(expected_nodes.keys())

    actual = []
    with open(OUTPUT_PATH, "r") as f:
        for line in f:
            if line.strip():
                actual.append(json.loads(line))

    assert len(actual) == len(expected_sorted_keys), (
        f"Expected {len(expected_sorted_keys)} records, got {len(actual)}"
    )

    for i, act in enumerate(actual):
        exp_key = expected_sorted_keys[i]
        exp = expected_nodes[exp_key]

        assert isinstance(act, dict), f"Record {i} must be a JSON object"
        assert set(act.keys()) == {"node_id", "pagerank", "component_size"}, (
            f"Record {i} does not strictly match the required schema: {set(act.keys())}"
        )
        assert type(act["node_id"]) is str, (
            f"Record {i} node_id should be a string, got {type(act['node_id'])}"
        )
        assert type(act["component_size"]) is int, (
            f"Record {i} component_size should be an integer, got {type(act['component_size'])}"
        )
        assert act.get("node_id") == exp["node_id"], (
            f"Record {i} node_id mismatch. Expected {exp['node_id']}, got {act.get('node_id')}"
        )
        assert act.get("component_size") == exp["component_size"], (
            f"Record {i} component_size mismatch. Expected {exp['component_size']}, got {act.get('component_size')}"
        )

        act_pr = act.get("pagerank")
        assert type(act_pr) is float, (
            f"Record {i} pagerank should be a float, got {type(act_pr)}"
        )
        assert abs(act_pr - exp["pagerank"]) < 1e-4, (
            f"Record {i} pagerank mismatch. Expected ~{exp['pagerank']}, got {act_pr}"
        )


def test_pipeline_script_exists_and_is_regular_file():
    assert os.path.exists(SCRIPT_PATH), "Missing /home/user/etl_pipeline.py"
    assert stat.S_ISREG(os.lstat(SCRIPT_PATH).st_mode), (
        "/home/user/etl_pipeline.py must be a regular file"
    )


def test_output_file_exists():
    run_pipeline()
    assert os.path.exists(OUTPUT_PATH), (
        "Output file /home/user/output/nodes.jsonl is missing"
    )


def test_output_content():
    run_pipeline()
    edges = get_edges()
    validate_output(edges)


def test_pipeline_processes_unseen_input():
    token = secrets.token_hex(6)
    names = [f"node_{token}_{i}" for i in range(9)]
    weights = [secrets.randbelow(900) / 100.0 + 1.0 for _ in range(9)]
    edges = [
        (names[0], names[1], weights[0]),
        (names[0], names[2], weights[1]),
        (names[1], names[2], weights[2]),
        (names[2], names[3], weights[3]),
        (names[3], names[0], weights[4]),
        (names[4], names[5], weights[5]),
        (names[5], names[6], weights[6]),
        (names[6], names[4], weights[7]),
        (names[7], names[8], weights[8]),
    ]

    try:
        with open(INPUT_PATH, "w") as f:
            f.write("src,dst,weight\n")
            for src, dst, weight in edges:
                f.write(f"{src},{dst},{weight}\n")
        run_pipeline()
        assert os.path.exists(OUTPUT_PATH), (
            "Pipeline did not materialize nodes.jsonl for unseen input"
        )
        validate_output(edges)
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(ORIGINAL_INPUT)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
