#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import subprocess
import xml.etree.ElementTree as ET

import pytest

SCRIPT_FILE = "/home/user/analyze_citations.py"
CSV_FILE = "/home/user/citations.csv"
SUMMARY_FILE = "/home/user/summary.json"
GRAPHML_FILE = "/home/user/top_paper_subgraph.graphml"


def read_edges(path):
    edges = []
    nodes = []
    seen = set()
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["source", "target"]
        for row in reader:
            source = int(row["source"])
            target = int(row["target"])
            edges.append((source, target))
            for node in (source, target):
                if node not in seen:
                    seen.add(node)
                    nodes.append(node)
    return nodes, edges


def expected_results(path):
    nodes, edges = read_edges(path)
    assert nodes

    successors = {node: [] for node in nodes}
    predecessors = {node: [] for node in nodes}
    for source, target in edges:
        if target not in successors[source]:
            successors[source].append(target)
            predecessors[target].append(source)

    # Match NetworkX's default PageRank parameters, including its default
    # convergence criterion and uniform dangling-node distribution.
    count = len(nodes)
    rank = {node: 1.0 / count for node in nodes}
    for _ in range(100):
        previous = rank
        rank = {node: 0.0 for node in nodes}
        dangling_sum = 0.85 * sum(
            previous[node] for node in nodes if not successors[node]
        )
        for node in nodes:
            if successors[node]:
                contribution = 0.85 * previous[node] / len(successors[node])
                for target in successors[node]:
                    rank[target] += contribution
        for node in nodes:
            rank[node] += dangling_sum / count + 0.15 / count
        error = sum(abs(rank[node] - previous[node]) for node in nodes)
        if error < count * 1.0e-6:
            break
    else:
        raise AssertionError("Independent PageRank calculation did not converge")

    top = max(nodes, key=lambda node: rank[node])

    ancestors = {top}
    pending = [top]
    while pending:
        node = pending.pop()
        for predecessor in predecessors[node]:
            if predecessor not in ancestors:
                ancestors.add(predecessor)
                pending.append(predecessor)

    memo = {top: 0}
    visiting = set()

    def distance_to_top(node):
        if node in memo:
            return memo[node]
        if node in visiting:
            raise AssertionError("Test input unexpectedly contains a cycle")
        visiting.add(node)
        distances = [
            distance_to_top(target) + 1
            for target in successors[node]
            if target in ancestors
        ]
        visiting.remove(node)
        assert distances, f"Ancestor {node} has no path to top paper {top}"
        memo[node] = max(distances)
        return memo[node]

    max_depth = max(distance_to_top(node) for node in ancestors)
    subgraph_edges = {
        (source, target)
        for source, target in edges
        if source in ancestors and target in ancestors
    }
    return top, round(rank[top], 4), max_depth, ancestors, subgraph_edges


def execute_script():
    assert os.path.isfile(SCRIPT_FILE), f"Expected Python script at {SCRIPT_FILE} is missing."
    for output in (SUMMARY_FILE, GRAPHML_FILE):
        if os.path.lexists(output):
            os.remove(output)
    result = subprocess.run(
        ["python3", SCRIPT_FILE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, f"Analysis script failed:\n{result.stdout}"
    assert os.path.isfile(SUMMARY_FILE), "The executed script did not create summary.json"
    assert os.path.isfile(GRAPHML_FILE), "The executed script did not create the GraphML file"


def parse_graphml(path):
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as exc:
        pytest.fail(f"File {path} is not valid XML/GraphML: {exc}")

    def local_name(tag):
        return tag.rsplit("}", 1)[-1]

    graph_elements = [element for element in root.iter() if local_name(element.tag) == "graph"]
    assert graph_elements, "GraphML file does not contain a graph element."
    assert graph_elements[0].attrib.get("edgedefault") == "directed", "Exported graph must be directed."

    nodes = {
        int(element.attrib["id"])
        for element in root.iter()
        if local_name(element.tag) == "node"
    }
    edges = {
        (int(element.attrib["source"]), int(element.attrib["target"]))
        for element in root.iter()
        if local_name(element.tag) == "edge"
    }
    return root, nodes, edges


def assert_outputs_match_dataset(path):
    expected_top, expected_score, expected_depth, expected_nodes, expected_edges = expected_results(path)

    with open(SUMMARY_FILE) as f:
        data = json.load(f)
    assert set(data) == {"top_paper_id", "pagerank_score", "max_depth_to_top"}
    assert type(data["top_paper_id"]) is int
    assert type(data["pagerank_score"]) is float
    assert type(data["max_depth_to_top"]) is int
    assert data["top_paper_id"] == expected_top
    assert data["pagerank_score"] == expected_score
    assert data["max_depth_to_top"] == expected_depth

    _, actual_nodes, actual_edges = parse_graphml(GRAPHML_FILE)
    assert actual_nodes == expected_nodes, "GraphML nodes are not exactly the top paper and its ancestors."
    assert actual_edges == expected_edges, "GraphML edges do not match the induced ancestor subgraph."


def test_script_exists_and_is_executed():
    execute_script()


def test_summary_json_exists_and_valid():
    assert os.path.isfile(SUMMARY_FILE), f"Expected summary file at {SUMMARY_FILE} is missing."
    with open(SUMMARY_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {SUMMARY_FILE} is not a valid JSON.")

    assert "top_paper_id" in data, "Missing 'top_paper_id' in summary.json"
    assert "pagerank_score" in data, "Missing 'pagerank_score' in summary.json"
    assert "max_depth_to_top" in data, "Missing 'max_depth_to_top' in summary.json"


def test_summary_json_values():
    with open(SUMMARY_FILE, 'r') as f:
        data = json.load(f)

    assert data["top_paper_id"] == 7, f"Expected top_paper_id to be 7, got {data['top_paper_id']}"
    assert data["max_depth_to_top"] == 7, f"Expected max_depth_to_top to be 7, got {data['max_depth_to_top']}"

    pr_score = data["pagerank_score"]
    assert isinstance(pr_score, float), f"Expected pagerank_score to be a float, got {type(pr_score)}"
    assert abs(pr_score - 0.2804) < 0.01, f"Expected pagerank_score to be approx 0.2804, got {pr_score}"

    # Also derive and check the exact rounded result from the supplied CSV.
    assert_outputs_match_dataset(CSV_FILE)


def test_graphml_file_exists_and_valid():
    assert os.path.isfile(GRAPHML_FILE), f"Expected GraphML file at {GRAPHML_FILE} is missing."
    try:
        tree = ET.parse(GRAPHML_FILE)
    except ET.ParseError:
        pytest.fail(f"File {GRAPHML_FILE} is not a valid XML/GraphML file.")

    root = tree.getroot()
    ns = {'graphml': 'http://graphml.graphdrawing.org/xmlns'}
    nodes = root.findall('.//graphml:node', ns)
    if not nodes:
        nodes = root.findall('.//node')

    assert len(nodes) > 0, "GraphML file does not contain any nodes."
    node_ids = [node.attrib.get('id') for node in nodes]
    assert '7' in node_ids or 7 in node_ids, "Top paper (node 7) is missing from the exported subgraph."
    assert '11' in node_ids or 11 in node_ids, "Node 11 (an ancestor) is missing from the exported subgraph."
    assert len(node_ids) == 13, f"Expected 13 nodes in the ancestor subgraph, got {len(node_ids)}"


def test_script_computes_results_for_unseen_inputs():
    with open(CSV_FILE, "rb") as f:
        original_csv = f.read()

    system_random = random.SystemRandom()
    try:
        for _ in range(2):
            count = system_random.randint(8, 14)
            labels = system_random.sample(range(100, 10000), count)

            # A chain guarantees every node reaches the final sink. Random extra
            # forward edges vary PageRank and the induced edge set per run.
            edges = [(labels[i], labels[i + 1]) for i in range(count - 1)]
            for i in range(count - 2):
                for j in range(i + 2, count):
                    if system_random.random() < 0.28:
                        edges.append((labels[i], labels[j]))
            system_random.shuffle(edges)

            with open(CSV_FILE, "w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(["source", "target"])
                writer.writerows(edges)

            execute_script()
            assert_outputs_match_dataset(CSV_FILE)
    finally:
        with open(CSV_FILE, "wb") as f:
            f.write(original_csv)
        # Restore the required final artifacts for the original supplied dataset.
        execute_script()
        assert_outputs_match_dataset(CSV_FILE)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
