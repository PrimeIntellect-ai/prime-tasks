#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import math
import pytest
import requests

def get_graph_data():
    path = "/home/user/transactions.jsonl"
    edges = {}
    nodes = set()

    with open(path, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            data = json.loads(line)
            u, v, w = data['sender'], data['receiver'], float(data['amount'])
            nodes.add(u)
            nodes.add(v)
            edges[(u, v)] = edges.get((u, v), 0.0) + w

    return list(nodes), edges

def compute_pagerank(nodes, edges, alpha=0.85, max_iter=100, tol=1e-6):
    N = len(nodes)
    if N == 0:
        return {}

    pr = {n: 1.0 / N for n in nodes}
    out_weight = {n: 0.0 for n in nodes}

    for (u, v), w in edges.items():
        out_weight[u] += w

    for _ in range(max_iter):
        new_pr = {n: (1.0 - alpha) / N for n in nodes}

        for (u, v), w in edges.items():
            new_pr[v] += alpha * pr[u] * (w / out_weight[u])

        dangling_sum = sum(pr[n] for n in nodes if out_weight[n] == 0)
        for n in nodes:
            new_pr[n] += alpha * dangling_sum / N

        err = sum(abs(new_pr[n] - pr[n]) for n in nodes)
        pr = new_pr
        if err < N * tol:
            break

    return pr

def compute_clusters(nodes, edges):
    adj = {n: [] for n in nodes}
    for u, v in edges.keys():
        adj[u].append(v)
        adj[v].append(u)

    visited = set()
    clusters = {}

    for n in nodes:
        if n not in visited:
            comp = []
            stack = [n]
            while stack:
                curr = stack.pop()
                if curr not in visited:
                    visited.add(curr)
                    comp.append(curr)
                    for neighbor in adj[curr]:
                        if neighbor not in visited:
                            stack.append(neighbor)

            cluster_id = min(comp)
            vol = 0.0
            for (u, v), w in edges.items():
                if u in comp and v in comp:
                    vol += w
            clusters[cluster_id] = vol

    return clusters

@pytest.fixture(scope="module")
def expected_data():
    nodes, edges = get_graph_data()
    pr = compute_pagerank(nodes, edges)
    clusters = compute_clusters(nodes, edges)
    return {"pagerank": pr, "clusters": clusters}

def test_health_endpoint():
    url = "http://127.0.0.1:8080/health"
    try:
        resp = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")

    assert resp.status_code == 200, f"Expected 200 OK for /health, got {resp.status_code}"
    data = resp.json()
    assert data.get("status") == "ok", f"Expected {{'status': 'ok'}}, got {data}"

def test_unauthorized_access():
    url = "http://127.0.0.1:8080/pagerank/N1"
    try:
        resp = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")

    assert resp.status_code == 401, f"Expected 401 Unauthorized for missing auth, got {resp.status_code}"

def test_pagerank_endpoint(expected_data):
    headers = {"Authorization": "Bearer SecretGraph77"}
    for node, expected_pr in expected_data["pagerank"].items():
        url = f"http://127.0.0.1:8080/pagerank/{node}"
        try:
            resp = requests.get(url, headers=headers, timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to {url}: {e}")

        assert resp.status_code == 200, f"Expected 200 OK for /pagerank/{node}, got {resp.status_code}. Response: {resp.text}"
        data = resp.json()
        assert "pagerank" in data, f"Response missing 'pagerank' field: {data}"
        assert math.isclose(data["pagerank"], expected_pr, rel_tol=1e-2, abs_tol=1e-2), \
            f"Expected PageRank for {node} to be ~{expected_pr}, got {data['pagerank']}"

def test_cluster_endpoint(expected_data):
    headers = {"Authorization": "Bearer SecretGraph77"}
    for cluster_id, expected_vol in expected_data["clusters"].items():
        url = f"http://127.0.0.1:8080/cluster/{cluster_id}"
        try:
            resp = requests.get(url, headers=headers, timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to {url}: {e}")

        assert resp.status_code == 200, f"Expected 200 OK for /cluster/{cluster_id}, got {resp.status_code}. Response: {resp.text}"
        data = resp.json()
        assert "total_volume" in data, f"Response missing 'total_volume' field: {data}"
        assert math.isclose(data["total_volume"], expected_vol, rel_tol=1e-5), \
            f"Expected total_volume for cluster {cluster_id} to be {expected_vol}, got {data['total_volume']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
