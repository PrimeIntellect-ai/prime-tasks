#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def compute_expected_coi(nodes_csv, edges_csv):
    nodes = {}
    with open(nodes_csv, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            nodes[int(row['id'])] = row

    edges = []
    with open(edges_csv, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            edges.append((int(row['source']), int(row['target']), row['type']))

    coi_names = []
    for p_id, p_data in nodes.items():
        if p_data['label'] != 'Person':
            continue

        ceo_of = [t for s, t, typ in edges if s == p_id and typ == 'CEO_of']
        sits_on = [t for s, t, typ in edges if s == p_id and typ == 'sits_on_board']

        matched = False
        for x in ceo_of:
            for y in sits_on:
                if any(s == y and t == x and typ == 'invested_in' for s, t, typ in edges):
                    coi_names.append(p_data['name'])
                    matched = True
                    break
            if matched:
                break

    return sorted(list(set(coi_names)))

def compute_expected_pagerank(nodes_csv, edges_csv):
    nodes = {}
    with open(nodes_csv, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            nodes[int(row['id'])] = row['name']

    edges = []
    with open(edges_csv, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            edges.append((int(row['source']), int(row['target'])))

    nodes_list = list(nodes.keys())
    N = len(nodes_list)
    if N == 0:
        return []

    out_degree = {n: 0 for n in nodes_list}
    for u, v in edges:
        out_degree[u] += 1

    pr = {n: 1.0 / N for n in nodes_list}
    d = 0.85

    # Power iteration for PageRank
    for _ in range(100):
        new_pr = {n: (1.0 - d) / N for n in nodes_list}
        for u, v in edges:
            new_pr[v] += d * pr[u] / out_degree[u]

        dangling_sum = sum(pr[n] for n in nodes_list if out_degree[n] == 0)
        if dangling_sum > 0:
            for n in nodes_list:
                new_pr[n] += d * dangling_sum / N

        pr = new_pr

    sorted_pr = sorted([(v, nodes[k]) for k, v in pr.items()], key=lambda x: (-x[0], x[1]))
    return [x[1] for x in sorted_pr[:3]]

def test_conflict_of_interest_output():
    """Verify that the conflict_of_interest.txt file is created with the correct content."""
    output_file = "/home/user/conflict_of_interest.txt"
    nodes_csv = "/home/user/data/nodes.csv"
    edges_csv = "/home/user/data/edges.csv"

    assert os.path.exists(output_file), f"Deliverable {output_file} is missing."

    expected_names = compute_expected_coi(nodes_csv, edges_csv)

    with open(output_file, 'r', encoding='utf-8') as f:
        actual_names = [line.strip() for line in f if line.strip()]

    assert actual_names == expected_names, (
        f"Contents of {output_file} do not match the expected conflict of interest pattern.\n"
        f"Expected: {expected_names}\n"
        f"Got: {actual_names}"
    )

def test_top_nodes_output():
    """Verify that the top_nodes.txt file is created with the correct top PageRank nodes."""
    output_file = "/home/user/top_nodes.txt"
    nodes_csv = "/home/user/data/nodes.csv"
    edges_csv = "/home/user/data/edges.csv"

    assert os.path.exists(output_file), f"Deliverable {output_file} is missing."

    expected_top_nodes = compute_expected_pagerank(nodes_csv, edges_csv)

    with open(output_file, 'r', encoding='utf-8') as f:
        actual_top_nodes = [line.strip() for line in f if line.strip()]

    assert actual_top_nodes == expected_top_nodes, (
        f"Contents of {output_file} do not match the expected top 3 PageRank nodes.\n"
        f"Expected: {expected_top_nodes}\n"
        f"Got: {actual_top_nodes}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
