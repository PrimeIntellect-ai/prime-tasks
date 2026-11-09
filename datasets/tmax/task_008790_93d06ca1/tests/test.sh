#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import sqlite3
import heapq
from collections import Counter, defaultdict


def build_graph(csv_path):
    graph = defaultdict(dict)
    nodes = set()
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            u = int(row['source'])
            v = int(row['target'])
            w = float(row['weight'])
            graph[u][v] = w
            nodes.add(u)
            nodes.add(v)
    return graph, nodes


def get_shortest_path(graph, start, target):
    queue = [(0.0, start, [start])]
    visited = set()
    while queue:
        cost, node, path = heapq.heappop(queue)
        if node in visited:
            continue
        visited.add(node)
        if node == target:
            return path
        for neighbor, weight in graph[node].items():
            if neighbor not in visited:
                heapq.heappush(queue, (cost + weight, neighbor, path + [neighbor]))
    return []


def get_betweenness_centrality(graph, nodes):
    cb = {v: 0.0 for v in nodes}
    for s in nodes:
        S = []
        P = {w: [] for w in nodes}
        sigma = {w: 0.0 for w in nodes}
        sigma[s] = 1.0
        d = {w: -1 for w in nodes}
        d[s] = 0
        Q = [s]

        while Q:
            v = Q.pop(0)
            S.append(v)
            for w in graph.get(v, {}):
                if d[w] < 0:
                    Q.append(w)
                    d[w] = d[v] + 1
                if d[w] == d[v] + 1:
                    sigma[w] += sigma[v]
                    P[w].append(v)

        delta = {w: 0.0 for w in nodes}
        while S:
            w = S.pop()
            for v in P[w]:
                if sigma[w] > 0:
                    delta[v] += (sigma[v] / sigma[w]) * (1.0 + delta[w])
            if w != s:
                cb[w] += delta[w]

    n = len(nodes)
    scale = 1.0 / ((n - 1) * (n - 2)) if n > 2 else 1.0
    for v in cb:
        cb[v] *= scale
    return cb


def test_database_and_index():
    db_path = '/home/user/network.db'
    csv_path = '/home/user/network.csv'
    assert os.path.exists(db_path), f"Database file {db_path} does not exist."
    assert os.path.exists(csv_path), f"Source data {csv_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='edges'")
    assert cursor.fetchone() is not None, "Table 'edges' does not exist in the database."

    cursor.execute("PRAGMA table_info('edges')")
    schema = cursor.fetchall()
    actual_columns = [(row[1].lower(), row[2].upper()) for row in schema]
    assert actual_columns == [('source', 'INTEGER'), ('target', 'INTEGER'), ('weight', 'REAL')], \
        f"The edges table has the wrong schema: {actual_columns}"

    with open(csv_path, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['source', 'target', 'weight'], "Unexpected source CSV header."
        expected_rows = [
            (int(row['source']), int(row['target']), float(row['weight']))
            for row in reader
        ]

    cursor.execute("SELECT source, target, weight FROM edges")
    database_rows = cursor.fetchall()
    assert Counter(database_rows) == Counter(expected_rows), \
        "The edges table does not contain exactly all rows from network.csv."

    cursor.execute("PRAGMA index_list('edges')")
    indexes = cursor.fetchall()
    assert len(indexes) > 0, "No indexes found on the 'edges' table."

    index_on_source = False
    for idx in indexes:
        idx_name = idx[1]
        escaped_name = idx_name.replace("'", "''")
        cursor.execute(f"PRAGMA index_info('{escaped_name}')")
        columns = [row[2] for row in cursor.fetchall()]
        if columns and columns[0] == 'source':
            index_on_source = True
            break

    assert index_on_source, "No index starting with 'source' column found on the 'edges' table."
    conn.close()


def test_query_plan():
    plan_path = '/home/user/plan.txt'
    db_path = '/home/user/network.db'
    assert os.path.exists(plan_path), f"Plan file {plan_path} does not exist."

    with open(plan_path, 'r') as f:
        raw_content = f.read().strip()
    content = raw_content.upper()

    assert 'USING INDEX' in content or 'SEARCH TABLE EDGES USING' in content, \
        "The query plan does not indicate that an index is being used."

    conn = sqlite3.connect(db_path)
    actual_plan = conn.execute(
        "EXPLAIN QUERY PLAN SELECT target, weight FROM edges WHERE source = 5;"
    ).fetchall()
    conn.close()

    assert actual_plan, "SQLite returned an empty execution plan."
    assert any('SEARCH' in str(row[3]).upper() and 'INDEX' in str(row[3]).upper()
               for row in actual_plan), \
        "SQLite's actual execution plan does not use an index."

    # Accept the common exact textual serializations produced by Python or SQLite
    # while requiring every saved value to come from the database's actual plan.
    valid_outputs = {
        '\n'.join(str(row[3]) for row in actual_plan),
        '\n'.join('|'.join(str(value) for value in row) for row in actual_plan),
        '\n'.join('\t'.join(str(value) for value in row) for row in actual_plan),
        '\n'.join(repr(tuple(row)) for row in actual_plan),
        repr([tuple(row) for row in actual_plan]),
    }
    assert raw_content in valid_outputs, \
        f"plan.txt is not the actual EXPLAIN QUERY PLAN output. Actual plan: {actual_plan}"


def test_graph_analytics():
    csv_path = '/home/user/network.csv'
    assert os.path.exists(csv_path), f"Source data {csv_path} is missing."

    graph, nodes = build_graph(csv_path)

    expected_path = get_shortest_path(graph, 1, 50)
    expected_path_str = ",".join(map(str, expected_path))

    path_file = '/home/user/path.txt'
    assert os.path.exists(path_file), f"Path file {path_file} does not exist."
    with open(path_file, 'r') as f:
        actual_path_str = f.read().strip()

    assert actual_path_str == expected_path_str, \
        f"Expected path '{expected_path_str}', but got '{actual_path_str}'."

    centrality = get_betweenness_centrality(graph, nodes)
    top_3 = sorted(centrality.items(), key=lambda x: x[1], reverse=True)[:3]
    expected_centrality = [f"{node},{score:.4f}" for node, score in top_3]

    centrality_file = '/home/user/centrality.csv'
    assert os.path.exists(centrality_file), f"Centrality file {centrality_file} does not exist."
    with open(centrality_file, 'r') as f:
        actual_centrality = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    assert actual_centrality == expected_centrality, \
        f"Expected centrality {expected_centrality}, but got {actual_centrality}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
