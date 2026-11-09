#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import pytest
import requests
import networkx as nx

BASE = "http://127.0.0.1:8080"


def get_upstream_data():
    edges_resp = requests.get("http://127.0.0.1:9001/edges", timeout=5)
    edges_resp.raise_for_status()
    nodes_resp = requests.get("http://127.0.0.1:9002/nodes", timeout=5)
    nodes_resp.raise_for_status()
    return edges_resp.json(), nodes_resp.json()


def expected_pagerank():
    edges, nodes = get_upstream_data()
    graph = nx.DiGraph()
    graph.add_nodes_from(n["tx_id"] for n in nodes)
    graph.add_edges_from((e["waiter"], e["holder"]) for e in edges)
    scores = nx.pagerank(graph, alpha=0.85)
    metadata = {n["tx_id"]: n["user"] for n in nodes}
    results = [
        {
            "tx_id": tx_id,
            "score": round(score, 4),
            "user": metadata.get(tx_id, "unknown"),
        }
        for tx_id, score in scores.items()
    ]
    results.sort(key=lambda item: (-item["score"], item["tx_id"]))
    return results


def get_json(path):
    try:
        response = requests.get(BASE + path, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to {path}: {exc}")
    assert response.status_code == 200, (
        f"Expected status 200 for {path}, got {response.status_code}. "
        f"Body: {response.text}"
    )
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response from {path} is not valid JSON: {response.text}")


def test_deadlocks_endpoint():
    data = get_json("/api/deadlocks")
    assert "deadlocks" in data, "Response JSON missing 'deadlocks' key"
    expected_deadlocks = [
        ["T7", "T8"],
        ["T1", "T2", "T3"],
        ["T4", "T5", "T6"],
    ]
    assert data["deadlocks"] == expected_deadlocks, (
        f"Expected deadlocks {expected_deadlocks}, got {data['deadlocks']}"
    )


def test_pagerank_endpoints():
    expected = expected_pagerank()

    data1 = get_json("/api/pagerank?page=1&limit=3")
    assert data1.get("page") == 1
    assert data1.get("limit") == 3
    assert data1.get("total_nodes") == len(expected)
    assert data1.get("results") == expected[:3]

    data2 = get_json("/api/pagerank?page=2&limit=3")
    assert data2.get("page") == 2
    assert data2.get("limit") == 3
    assert data2.get("total_nodes") == len(expected)
    assert data2.get("results") == expected[3:6]

    # Exercise a different limit and the final partial page, ensuring pagination
    # is applied to the complete, correctly ordered PageRank result set.
    data3 = get_json("/api/pagerank?page=3&limit=3")
    assert data3.get("page") == 3
    assert data3.get("limit") == 3
    assert data3.get("total_nodes") == len(expected)
    assert data3.get("results") == expected[6:9]

    default_data = get_json("/api/pagerank")
    assert default_data.get("page") == 1
    assert default_data.get("limit") == 10
    assert default_data.get("total_nodes") == len(expected)
    assert default_data.get("results") == expected[:10]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
