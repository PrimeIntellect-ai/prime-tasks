#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils
    pip3 install pytest networkx pyinstaller

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.py
import json
import sys
import networkx as nx

def solve(file_path):
    with open(file_path, 'r') as f:
        data = json.load(f)
    G = nx.DiGraph()
    for n in data['nodes']:
        G.add_node(n['id'], size=n['size'])
    for e in data['edges']:
        G.add_edge(e['source'], e['target'], weight=e['transfer_time'])

    in_degrees = dict(G.in_degree())
    roots = [n for n, d in in_degrees.items() if d == 0]

    scores = []
    for n in G.nodes():
        size = G.nodes[n]['size']
        if n in roots:
            min_dist = 0
        else:
            min_dist = float('inf')
            for r in roots:
                try:
                    dist = nx.shortest_path_length(G, source=r, target=n, weight='weight')
                    if dist < min_dist:
                        min_dist = dist
                except nx.NetworkXNoPath:
                    pass
            if min_dist == float('inf'):
                min_dist = 0 # Fallback for unreachable nodes
        score = size * (1 + min_dist)
        scores.append((score, n))

    scores.sort(key=lambda x: (-x[0], x[1]))
    return ",".join([str(x[1]) for x in scores])

if __name__ == "__main__":
    print(solve(sys.argv[1]))
EOF

    pyinstaller --onefile /tmp/oracle.py --distpath /app --name backup_path_oracle
    rm -rf /tmp/oracle.py build backup_path_oracle.spec

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
