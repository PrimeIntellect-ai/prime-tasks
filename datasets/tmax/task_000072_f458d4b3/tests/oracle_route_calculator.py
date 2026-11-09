import sys
import sqlite3
import heapq

def get_shortest_path(start, end):
    conn = sqlite3.connect('/app/routing_backup.db')
    c = conn.cursor()

    c.execute("SELECT id, name FROM nodes")
    nodes = {row[1]: row[0] for row in c.fetchall()}

    if start not in nodes or end not in nodes:
        return -1

    start_id = nodes[start]
    end_id = nodes[end]

    bad_nodes = {'NodeDelta', 'NodeSigma', 'NodeTau'}
    bad_ids = {nodes[n] for n in bad_nodes if n in nodes}

    c.execute("SELECT source_id, target_id, weight FROM edges NOT INDEXED")
    graph = {}
    for src, tgt, w in c.fetchall():
        if src in bad_ids or tgt in bad_ids:
            continue
        if src not in graph:
            graph[src] = []
        graph[src].append((tgt, w))

    pq = [(0, start_id)]
    dist = {start_id: 0}

    while pq:
        d, u = heapq.heappop(pq)

        if d > dist.get(u, float('inf')):
            continue

        if u == end_id:
            return d

        for v, w in graph.get(u, []):
            if dist.get(v, float('inf')) > d + w:
                dist[v] = d + w
                heapq.heappush(pq, (dist[v], v))

    return -1

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(1)
    print(get_shortest_path(sys.argv[1], sys.argv[2]))
