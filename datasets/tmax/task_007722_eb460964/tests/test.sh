#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import csv
import heapq
import random
import secrets
import subprocess
import pytest

NODES_PATH = "/home/user/nodes.csv"
EDGES_PATH = "/home/user/edges.csv"
RESULTS_PATH = "/home/user/results.json"
PIPELINE_PATH = "/home/user/pipeline.go"
PIPELINE_BIN = "/tmp/submission-pipeline"


def compute_expected_results():
    if not os.path.exists(NODES_PATH) or not os.path.exists(EDGES_PATH):
        return []

    nodes = {}
    with open(NODES_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            nodes[row['id']] = {'name': row['name'], 'type': row['type']}

    graph = {node: [] for node in nodes}
    with open(EDGES_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            u = row['source']
            v = row['target']
            w = int(row['distance'])
            if u not in graph:
                graph[u] = []
            graph[u].append((v, w))

    distances = {n: float('inf') for n in graph}
    distances['N001'] = 0
    pq = [(0, 'N001')]

    while pq:
        d, u = heapq.heappop(pq)
        if d > distances.get(u, float('inf')):
            continue
        for v, w in graph.get(u, []):
            nd = d + w
            if nd < distances.get(v, float('inf')):
                distances[v] = nd
                heapq.heappush(pq, (nd, v))

    results = []
    for node_id, dist in distances.items():
        if node_id in nodes and nodes[node_id]['type'] == 'warehouse' and dist <= 150:
            results.append({
                "id": node_id,
                "name": nodes[node_id]['name'],
                "distance": dist
            })

    results.sort(key=lambda x: (-x['distance'], x['id']))
    return results[3:6]


def run_pipeline():
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    proc = subprocess.run(
        [PIPELINE_BIN], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert proc.returncode == 0, "pipeline execution failed:\n" + proc.stdout + proc.stderr
    assert os.path.isfile(RESULTS_PATH), "pipeline did not create /home/user/results.json"
    with open(RESULTS_PATH, 'r', encoding='utf-8') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Pipeline produced invalid JSON: {exc}")


def test_00_pipeline_exists_compiles_and_runs():
    assert os.path.isfile(PIPELINE_PATH), f"File {PIPELINE_PATH} is missing or is not a regular file."
    proc = subprocess.run(
        ["go", "build", "-o", PIPELINE_BIN, PIPELINE_PATH],
        cwd="/home/user", text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=40
    )
    assert proc.returncode == 0, "pipeline.go does not compile:\n" + proc.stdout + proc.stderr
    actual = run_pipeline()
    assert actual == compute_expected_results(), \
        f"Executed pipeline produced {actual}, expected {compute_expected_results()}."


def test_results_json():
    results_path = "/home/user/results.json"
    assert os.path.isfile(results_path), f"File {results_path} is missing."

    with open(results_path, 'r', encoding='utf-8') as f:
        try:
            actual_results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} does not contain valid JSON.")

    expected_results = compute_expected_results()
    assert actual_results == expected_results, f"Expected results {expected_results}, but got {actual_results}."


def write_hidden_dataset(seed):
    rng = random.Random(seed)
    suffixes = [secrets.token_hex(3).upper() for _ in range(10)]
    warehouses = ["W" + s for s in suffixes[:8]]
    unreachable = "U" + suffixes[8]
    over_limit = "Z" + suffixes[9]
    transit = "X" + secrets.token_hex(3).upper()

    nodes = [("N001", "Factory-" + secrets.token_hex(2), "factory"),
             (transit, "Transit-" + secrets.token_hex(2), "retail")]
    for i, wid in enumerate(warehouses):
        nodes.append((wid, f"Hidden Warehouse {i}-{secrets.token_hex(2)}", "warehouse"))
    nodes.extend([
        (unreachable, "Unreachable-" + secrets.token_hex(2), "warehouse"),
        (over_limit, "Far-" + secrets.token_hex(2), "warehouse")
    ])

    # Includes an alternate shorter route, equal-distance warehouses, a cutoff
    # failure, and reverse-only reachability to exercise all required behavior.
    direct = [140, 120, 100, 80, 80, 40, 20, 150]
    edges = [("N001", wid, dist) for wid, dist in zip(warehouses, direct)]
    edges.extend([
        ("N001", transit, 11),
        (transit, warehouses[0], 22),
        ("N001", over_limit, 151 + rng.randrange(1, 30)),
        (unreachable, "N001", 1)
    ])
    rng.shuffle(nodes)
    rng.shuffle(edges)

    with open(NODES_PATH, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(["id", "name", "type"])
        writer.writerows(nodes)
    with open(EDGES_PATH, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(["source", "target", "distance"])
        writer.writerows(edges)


def test_pipeline_on_unseen_inputs():
    with open(NODES_PATH, 'rb') as f:
        original_nodes = f.read()
    with open(EDGES_PATH, 'rb') as f:
        original_edges = f.read()

    try:
        for _ in range(2):
            write_hidden_dataset(secrets.randbits(64))
            expected = compute_expected_results()
            actual = run_pipeline()
            assert actual == expected, f"On an unseen CSV graph, expected {expected}, got {actual}."
    finally:
        with open(NODES_PATH, 'wb') as f:
            f.write(original_nodes)
        with open(EDGES_PATH, 'wb') as f:
            f.write(original_edges)
        run_pipeline()


def strip_cypher_comments(text):
    text = re.sub(r'/\\*.*?\\*/', ' ', text, flags=re.S)
    text = re.sub(r'//[^\\n]*', ' ', text)
    return text


def assert_balanced(text):
    pairs = {')': '(', ']': '[', '}': '{'}
    stack = []
    quote = None
    escaped = False
    for ch in text:
        if quote:
            if escaped:
                escaped = False
            elif ch == '\\\\':
                escaped = True
            elif ch == quote:
                quote = None
            continue
        if ch in "'\\\"":
            quote = ch
        elif ch in "([{":
            stack.append(ch)
        elif ch in ")]}":
            assert stack and stack.pop() == pairs[ch], "Unbalanced Cypher delimiters."
    assert quote is None and not stack, "Unbalanced Cypher delimiters or string literal."


def test_cypher_query():
    query_path = "/home/user/query.cypher"
    assert os.path.isfile(query_path), f"File {query_path} is missing."

    with open(query_path, 'r', encoding='utf-8') as f:
        raw = f.read()
        content = raw.upper()

    # Preserve the original assertions.
    required_keywords = ["MATCH", "WHERE", "ORDER BY", "DESC", "SKIP 3", "LIMIT 3"]
    for kw in required_keywords:
        assert kw in content, f"Expected keyword '{kw}' missing in {query_path}."
    content_lower = content.lower()
    assert "n001" in content_lower, f"Expected starting node 'N001' missing in {query_path}."
    assert "warehouse" in content_lower, f"Expected node type 'warehouse' missing in {query_path}."
    assert "150" in content_lower, f"Expected distance limit '150' missing in {query_path}."

    # Validate an actual connected Cypher statement rather than accepting words
    # placed in comments or arbitrary prose.
    q = strip_cypher_comments(raw).strip()
    assert q, "Cypher query is empty after comments are removed."
    assert_balanced(q)
    assert q.count(';') <= 1 and (';' not in q or q.rstrip().endswith(';')), \
        "query.cypher must contain one query statement."

    flags = re.I | re.S
    start_nodes = re.findall(r'\\(\\s*([A-Za-z_]\\w*)\\s*:\\s*Facility\\s*([^)]*)\\)', q, flags)
    assert start_nodes, "Query must match labeled Facility nodes."

    start_var = None
    warehouse_var = None
    for var, body in start_nodes:
        if re.search(r"\\bid\\s*:\\s*['\"]N001['\"]", body, re.I) or \
           re.search(rf"\\b{re.escape(var)}\\.id\\s*=\\s*['\"]N001['\"]", q, re.I):
            start_var = var
        if re.search(r"\\btype\\s*:\\s*['\"]warehouse['\"]", body, re.I) or \
           re.search(rf"\\b{re.escape(var)}\\.type\\s*=\\s*['\"]warehouse['\"]", q, re.I):
            warehouse_var = var
    assert start_var, "Query must constrain a Facility variable to id 'N001'."
    assert warehouse_var, "Query must constrain a Facility variable to type 'warehouse'."

    route = re.search(
        rf"([A-Za-z_]\\w*)\\s*=\\s*(shortestPath\\s*\\()?\\s*"
        rf"\\(\\s*{re.escape(start_var)}(?:\\s*:\\s*Facility)?[^)]*\\)\\s*"
        rf"-\\s*\\[[^]]*:\\s*ROUTE[^]]*\\*[^]]*\\]\\s*->\\s*"
        rf"\\(\\s*{re.escape(warehouse_var)}(?:\\s*:\\s*Facility)?[^)]*\\)", q, flags)
    assert route, "Query must assign a directed variable-length :ROUTE path from N001 to the warehouse."
    path_var = route.group(1)

    assert re.search(rf"relationships\\s*\\(\\s*{re.escape(path_var)}\\s*\\)", q, flags), \
        "Query must sum relationships from the matched path."
    assert re.search(r"\\.distance\\b", q, flags), \
        "Query must use each ROUTE relationship's distance property."
    has_reduce = re.search(r"\\breduce\\s*\\([^)]*relationships\\s*\\(", q, flags)
    has_sum = re.search(r"\\bsum\\s*\\(\\s*[A-Za-z_]\\w*\\.distance\\s*\\)", q, flags)
    assert has_reduce or has_sum, "Query must calculate total path distance with REDUCE or SUM."

    # A variable-length path query needs aggregation to select the minimum total;
    # shortestPath is also explicitly permitted by the task.
    assert route.group(2) or re.search(r"\\bmin\\s*\\(", q, flags), \
        "Variable-length paths must be reduced to the minimum total distance per warehouse."

    match_pos = re.search(r"\\bMATCH\\b", q, flags)
    where_pos = re.search(r"\\bWHERE\\b", q, flags)
    return_pos = re.search(r"\\bRETURN\\b", q, flags)
    order_pos = re.search(r"\\bORDER\\s+BY\\b", q, flags)
    skip_pos = re.search(r"\\bSKIP\\s+3\\b", q, flags)
    limit_pos = re.search(r"\\bLIMIT\\s+3\\b", q, flags)
    assert all((match_pos, where_pos, return_pos, order_pos, skip_pos, limit_pos)), \
        "Query is missing a required Cypher clause."
    assert match_pos.start() < where_pos.start() < return_pos.start() < order_pos.start() < skip_pos.start() < limit_pos.start(), \
        "Cypher clauses are not in a functional retrieval order."

    where_clause = q[where_pos.start():return_pos.start()]
    assert re.search(r"<=\\s*150\\b", where_clause, flags), \
        "WHERE must apply the total-distance cutoff of 150."

    return_clause = q[return_pos.end():order_pos.start()]
    assert re.search(rf"\\b{re.escape(warehouse_var)}\\.id\\b", return_clause, flags), \
        "RETURN must include the warehouse id."
    assert re.search(rf"\\b{re.escape(warehouse_var)}\\.name\\b", return_clause, flags), \
        "RETURN must include the warehouse name."
    assert re.search(r"\\bdistance\\b", return_clause, flags), \
        "RETURN must include the calculated distance."

    order_clause = q[order_pos.end():skip_pos.start()]
    ordering = re.search(r"([A-Za-z_]\\w*(?:\\.[A-Za-z_]\\w*)?)\\s+DESC\\s*,\\s*"
                         r"([A-Za-z_]\\w*(?:\\.[A-Za-z_]\\w*)?)\\s+ASC", order_clause, flags)
    assert ordering, "ORDER BY must contain distance DESC followed by id ASC."
    assert "distance" in ordering.group(1).lower(), "Primary ordering must be by distance DESC."
    assert ordering.group(2).lower() == "id" or ordering.group(2).lower().endswith(".id"), \
        "Tie-breaking ordering must be by id ASC."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
