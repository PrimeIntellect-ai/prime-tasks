#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/evaluate_graph.py"
ORACLE_PATH = "/app/compliance_oracle"
CLEAN_CORPUS_DIR = "/home/user/corpus/clean"
EVIL_CORPUS_DIR = "/home/user/corpus/evil"


def run_submission(filepath, timeout=8):
    return subprocess.run(
        ["python3", SCRIPT_PATH, filepath],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def assert_classification(result, expected_code, filepath):
    expected_output = "NON-COMPLIANT" if expected_code == 1 else "COMPLIANT"
    assert result.returncode == expected_code, (
        f"Wrong exit code for {filepath}: expected {expected_code}, got "
        f"{result.returncode}. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected_output, (
        f"Wrong output for {filepath}: expected {expected_output!r}, "
        f"got {result.stdout!r}"
    )


def oracle_expected(graph):
    nodes = {node["id"]: node for node in graph["nodes"]}
    adjacency = {node_id: [] for node_id in nodes}
    for edge in graph["edges"]:
        if edge["source"] in nodes and edge["target"] in nodes:
            adjacency[edge["source"]].append(edge["target"])

    paths = []

    def visit(node_id, current, seen):
        node = nodes[node_id]
        new_path = current + [node["label"]]
        if node["type"] == "Resource":
            paths.append(new_path)
            return
        for target in adjacency[node_id]:
            if target not in seen:
                visit(target, new_path, seen | {target})

    for node_id, node in nodes.items():
        if node["type"] == "User":
            visit(node_id, [], {node_id})

    for path in paths:
        result = subprocess.run(
            [ORACLE_PATH, ",".join(path)], capture_output=True, timeout=3
        )
        assert result.returncode in (0, 1), "Compliance oracle returned an invalid code"
        if result.returncode == 1:
            return 1
    return 0


class GraphBuilder:
    def __init__(self, token):
        self.token = token
        self.nodes = []
        self.edges = []

    def node(self, node_type, label):
        node_id = "id_" + secrets.token_hex(7)
        self.nodes.append({"id": node_id, "type": node_type, "label": label})
        return node_id

    def edge(self, source, target):
        self.edges.append({"source": source, "target": target})

    def graph(self):
        random.SystemRandom().shuffle(self.nodes)
        random.SystemRandom().shuffle(self.edges)
        return {"nodes": self.nodes, "edges": self.edges}


def dynamic_graphs():
    token = secrets.token_hex(8)
    graphs = []

    # Ordinary legal path.
    b = GraphBuilder(token)
    u = b.node("User", "FTE_" + token)
    r = b.node("Role", "Analyst_" + token)
    x = b.node("Resource", "PII_" + token)
    b.edge(u, r); b.edge(r, x)
    graphs.append(b.graph())

    # Deep illegal path requiring traversal through several nodes.
    b = GraphBuilder(token)
    u = b.node("User", "Contractor_" + token)
    a = b.node("Group", "Team_" + token)
    c = b.node("Role", "Reviewer_" + token)
    d = b.node("Service", "Internal_" + token)
    x = b.node("Resource", "Financial_" + token)
    b.edge(u, a); b.edge(a, c); b.edge(c, d); b.edge(d, x)
    graphs.append(b.graph())

    # A gateway on the actual path makes it legal.
    b = GraphBuilder(token)
    u = b.node("User", "Contractor_" + token)
    g = b.node("Gateway", "VPN_Proxy_" + token)
    x = b.node("Resource", "Financial_" + token)
    b.edge(u, g); b.edge(g, x)
    graphs.append(b.graph())

    # One safe branch must not hide a separate illegal branch.
    b = GraphBuilder(token)
    u = b.node("User", "Contractor_" + token)
    safe = b.node("Gateway", "Audit_Gateway_" + token)
    unsafe = b.node("Role", "Admin_" + token)
    p = b.node("Resource", "PII_" + token)
    f = b.node("Resource", "Financial_" + token)
    b.edge(u, safe); b.edge(safe, p); b.edge(u, unsafe); b.edge(unsafe, f)
    graphs.append(b.graph())

    # Relevant words in disconnected components do not form an access path.
    b = GraphBuilder(token)
    contractor = b.node("User", "Contractor_" + token)
    dead = b.node("Role", "No_Access_" + token)
    employee = b.node("User", "FTE_" + token)
    financial = b.node("Resource", "Financial_" + token)
    b.edge(contractor, dead); b.edge(employee, financial)
    graphs.append(b.graph())

    # A disconnected gateway must not sanitize an illegal path.
    b = GraphBuilder(token)
    u = b.node("User", "Contractor_" + token)
    role = b.node("Role", "Operator_" + token)
    x = b.node("Resource", "PII_" + token)
    gateway = b.node("Gateway", "Audit_Gateway_" + token)
    orphan = b.node("Service", "Orphan_" + token)
    b.edge(u, role); b.edge(role, x); b.edge(gateway, orphan)
    graphs.append(b.graph())

    # Only paths beginning at User nodes count.
    b = GraphBuilder(token)
    service = b.node("Service", "Contractor_" + token)
    x = b.node("Resource", "Financial_" + token)
    user = b.node("User", "Visitor_" + token)
    public = b.node("Resource", "Public_" + token)
    b.edge(service, x); b.edge(user, public)
    graphs.append(b.graph())

    # A contractor chain that never terminates at a Resource is not a path.
    b = GraphBuilder(token)
    u = b.node("User", "Contractor_" + token)
    a = b.node("Role", "Financial_" + token)
    terminal = b.node("Service", "Terminal_" + token)
    b.edge(u, a); b.edge(a, terminal)
    graphs.append(b.graph())

    # Shared subgraphs and multiple users/resources.
    b = GraphBuilder(token)
    cuser = b.node("User", "Contractor_" + token)
    euser = b.node("User", "Employee_" + token)
    shared = b.node("Role", "Shared_" + token)
    proxy = b.node("Gateway", "VPN_Proxy_" + token)
    public = b.node("Resource", "Public_" + token)
    pii = b.node("Resource", "PII_" + token)
    b.edge(cuser, shared); b.edge(euser, shared)
    b.edge(shared, public); b.edge(shared, proxy); b.edge(proxy, pii)
    graphs.append(b.graph())

    return graphs


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"The required script was not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a valid file"


def test_clean_corpus_accepted():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.json"))
    assert len(clean_files) > 0, f"No JSON files found in the clean corpus directory at {CLEAN_CORPUS_DIR}."

    failed_files = []
    for filepath in clean_files:
        result = run_submission(filepath)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))
        else:
            assert_classification(result, 0, filepath)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_files)}")


def test_evil_corpus_rejected():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.json"))
    assert len(evil_files) > 0, f"No JSON files found in the evil corpus directory at {EVIL_CORPUS_DIR}."

    failed_files = []
    for filepath in evil_files:
        result = run_submission(filepath)
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))
        else:
            assert_classification(result, 1, filepath)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed: {', '.join(failed_files)}")


def test_fresh_hidden_graphs_against_oracle():
    assert os.path.isfile(ORACLE_PATH) and os.access(ORACLE_PATH, os.X_OK)
    graphs = dynamic_graphs()
    expected_codes = [oracle_expected(graph) for graph in graphs]
    assert 0 in expected_codes and 1 in expected_codes

    with tempfile.TemporaryDirectory(prefix="graphcheck_" + secrets.token_hex(6) + "_") as directory:
        for graph, expected in zip(graphs, expected_codes):
            filepath = os.path.join(directory, secrets.token_hex(12) + ".json")
            with open(filepath, "w", encoding="utf-8") as handle:
                json.dump(graph, handle)
            result = run_submission(filepath)
            assert_classification(result, expected, filepath)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
