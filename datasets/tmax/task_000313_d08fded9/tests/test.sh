#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import secrets
import socket
import sqlite3
import threading
import time
import pytest


def test_database_index_exists():
    db_path = "/app/data/graph.db"
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get all indexes for the edges table
    cursor.execute("PRAGMA index_list('edges');")
    indexes = cursor.fetchall()

    assert len(indexes) > 0, "No index found on the 'edges' table. You must create an index to optimize the query."

    index_on_parent_id = False
    for idx in indexes:
        idx_name = idx[1]
        cursor.execute(f"PRAGMA index_info('{idx_name}');")
        columns = cursor.fetchall()
        # columns format: (seqno, cid, name)
        if any(col[2] == 'parent_id' for col in columns):
            index_on_parent_id = True
            break

    assert index_on_parent_id, "No index found specifically on the 'parent_id' column in the 'edges' table."
    conn.close()


def send_request(node_id):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    s.connect(('127.0.0.1', 8888))
    s.sendall(f"{node_id}\n".encode('utf-8'))
    data = s.recv(1024).decode('utf-8').strip()
    s.close()
    return data


def test_service_responses():
    try:
        resp1 = send_request(1)
        assert resp1 == "7", f"Expected descendant count '7' for node 1, got '{resp1}'"
    except Exception as e:
        pytest.fail(f"Failed to communicate with the service for node 1: {e}")

    try:
        resp2 = send_request(2)
        assert resp2 == "4", f"Expected descendant count '4' for node 2, got '{resp2}'"
    except Exception as e:
        pytest.fail(f"Failed to communicate with the service for node 2: {e}")


def test_concurrency():
    def worker(node_id, results, index):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(5.0)
            s.connect(('127.0.0.1', 8888))
            # Sleep slightly to ensure multiple connections are open simultaneously
            time.sleep(0.5)
            s.sendall(f"{node_id}\n".encode('utf-8'))
            data = s.recv(1024).decode('utf-8').strip()
            s.close()
            results[index] = data
        except Exception as e:
            results[index] = str(e)

    results = [None, None]
    t1 = threading.Thread(target=worker, args=(1, results, 0))
    t2 = threading.Thread(target=worker, args=(2, results, 1))

    t1.start()
    t2.start()

    t1.join(timeout=10)
    t2.join(timeout=10)

    assert not t1.is_alive() and not t2.is_alive(), "Threads hung, likely due to a deadlock. Did you add 'fork' to the socat command?"
    assert results[0] == "7", f"Concurrent request 1 failed or returned wrong result: {results[0]}"
    assert results[1] == "4", f"Concurrent request 2 failed or returned wrong result: {results[1]}"


def test_randomized_graph_queries_and_concurrency():
    # Add a disconnected, unpredictable tree after the service has started. This
    # ensures the API performs the recursive traversal rather than hardcoding the
    # two nodes from the original database.
    conn = sqlite3.connect('/app/data/graph.db')
    cursor = conn.cursor()
    node_count = 13

    while True:
        base = 1000000000 + secrets.randbelow(800000000)
        nodes = [base + i for i in range(node_count)]
        missing_node = base + node_count + 100
        candidates = nodes + [missing_node]
        placeholders = ','.join('?' for _ in candidates)
        cursor.execute(
            f"SELECT 1 FROM edges WHERE parent_id IN ({placeholders}) OR child_id IN ({placeholders}) LIMIT 1",
            candidates + candidates,
        )
        if cursor.fetchone() is None:
            break

    children = {node: [] for node in nodes}
    inserted_edges = []
    for i in range(1, node_count):
        parent = nodes[secrets.randbelow(i)]
        child = nodes[i]
        children[parent].append(child)
        inserted_edges.append((parent, child))

    cursor.executemany(
        "INSERT INTO edges(parent_id, child_id) VALUES (?, ?)", inserted_edges
    )
    conn.commit()
    conn.close()

    def expected_count(start):
        count = 0
        stack = list(children.get(start, []))
        while stack:
            node = stack.pop()
            count += 1
            stack.extend(children.get(node, []))
        return str(count)

    query_nodes = nodes + [missing_node]
    expected = {node: expected_count(node) for node in query_nodes}

    for node in query_nodes:
        actual = send_request(node)
        assert actual == expected[node], (
            f"Expected descendant count {expected[node]!r} for randomized node "
            f"{node}, got {actual!r}"
        )

    results = [None] * len(query_nodes)

    def worker(index, node):
        try:
            results[index] = send_request(node)
        except Exception as e:
            results[index] = f"ERROR: {e}"

    threads = [
        threading.Thread(target=worker, args=(i, node))
        for i, node in enumerate(query_nodes)
    ]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=10)

    assert all(not thread.is_alive() for thread in threads), (
        "Concurrent randomized requests hung"
    )
    for i, node in enumerate(query_nodes):
        assert results[i] == expected[node], (
            f"Concurrent randomized request for node {node} expected "
            f"{expected[node]!r}, got {results[i]!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
