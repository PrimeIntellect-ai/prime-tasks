#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/simple_graph
    mkdir -p /data

    cat << 'EOF' > /app/simple_graph/engine.py
import sqlite3
import csv

class GraphEngine:
    def __init__(self, nodes_path, edges_path):
        self.conn = sqlite3.connect(':memory:', check_same_thread=False)
        self._load_data(nodes_path, edges_path)

    def _load_data(self, nodes_path, edges_path):
        self.conn.execute("CREATE TABLE nodes (id TEXT PRIMARY KEY, name TEXT)")
        self.conn.execute("CREATE TABLE edges (source_id TEXT, target_id TEXT)")

        with open(nodes_path, 'r') as f:
            dr = csv.DictReader(f)
            for row in dr:
                self.conn.execute("INSERT INTO nodes (id, name) VALUES (?, ?)", (row['id'], row['name']))

        with open(edges_path, 'r') as f:
            dr = csv.DictReader(f)
            for row in dr:
                self.conn.execute("INSERT INTO edges (source_id, target_id) VALUES (?, ?)", (row['source_id'], row['target_id']))
        self.conn.commit()

    def get_neighbors(self, node_id):
        cur = self.conn.execute("SELECT e.target_id FROM edges e, nodes n WHERE n.id = ?", (node_id,))
        return [row[0] for row in cur.fetchall()]

    def shortest_path(self, src, dst):
        from collections import deque
        queue = deque([[src]])
        visited = set([src])
        while queue:
            path = queue.popleft()
            node = path[-1]
            if node == dst:
                return path
            for neighbor in self.get_neighbors(node):
                if neighbor not in visited:
                    visited.add(neighbor)
                    queue.append(path + [neighbor])
        return None
EOF

    cat << 'EOF' > /app/simple_graph/server.py
import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs
from engine import GraphEngine

class GraphRequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == '/shortest_path':
            qs = parse_qs(parsed.query)
            src = qs.get('src', [None])[0]
            dst = qs.get('dst', [None])[0]
            if src and dst:
                path = self.server.engine.shortest_path(src, dst)
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'path': path}).encode())
            else:
                self.send_response(400)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--nodes', required=True)
    parser.add_argument('--edges', required=True)
    args = parser.parse_args()

    engine = GraphEngine(args.nodes, args.edges)
    server = HTTPServer(('0.0.0.0', args.port), GraphRequestHandler)
    server.engine = engine
    print(f"Starting server on port {args.port}...")
    server.serve_forever()
EOF

    cat << 'EOF' > /tmp/generate_data.py
import csv
import random

nodes = [{"id": str(i), "name": f"Node_{i}"} for i in range(1, 1001)]
with open('/data/nodes.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['id', 'name'])
    writer.writeheader()
    writer.writerows(nodes)

edges = []
path = [1, 10, 20, 30, 40, 50]
for i in range(len(path)-1):
    edges.append({"source_id": str(path[i]), "target_id": str(path[i+1])})

for _ in range(5000):
    u = random.randint(1, 1000)
    v = random.randint(1, 1000)
    if u != v:
        edges.append({"source_id": str(u), "target_id": str(v)})

with open('/data/edges.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['source_id', 'target_id'])
    writer.writeheader()
    writer.writerows(edges)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
