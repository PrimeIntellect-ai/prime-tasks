#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc wget unzip
    pip3 install pytest networkx

    mkdir -p /app/sqlite
    mkdir -p /app/data

    # Download real SQLite amalgamation to ensure the agent can actually compile and run it
    wget -q https://www.sqlite.org/2023/sqlite-amalgamation-3430000.zip -O /tmp/sqlite.zip
    unzip -q /tmp/sqlite.zip -d /tmp/
    cp /tmp/sqlite-amalgamation-3430000/sqlite3.c /app/sqlite/
    cp /tmp/sqlite-amalgamation-3430000/sqlite3.h /app/sqlite/
    rm -rf /tmp/sqlite*

    # Create the broken build script
    cat << 'EOF' > /app/sqlite/build.sh
#!/bin/bash
# Usage: ./build.sh <source.c> <output_binary>
gcc -O3 -I/app/sqlite $1 /app/sqlite/sqlite3.c -o $2 -lpthead -ldl
EOF
    chmod 0755 /app/sqlite/build.sh

    # Generate the network graph and truth data
    cat << 'EOF' > /tmp/gen_data.py
import os
import random
import networkx as nx

G = nx.erdos_renyi_graph(200, 0.05, directed=True, seed=42)
nx.relabel_nodes(G, {0: 'NODE_START', 199: 'NODE_END'}, copy=False)

path = ['NODE_START', 'N1', 'N2', 'N3', 'NODE_END']
edges = list(G.edges(data=True))

with open('/app/data/network.csv', 'w') as f:
    for u, v, data in edges:
        if u not in path and v not in path:
            weight = round(random.uniform(1.0, 10.0), 2)
            G[u][v]['weight'] = weight
            f.write(f"{u},{v},{weight}\n")

    guaranteed_weights = [2.5, 3.1, 1.4, 4.2]
    for i in range(len(path)-1):
        G.add_edge(path[i], path[i+1], weight=guaranteed_weights[i])
        f.write(f"{path[i]},{path[i+1]},{guaranteed_weights[i]}\n")

true_shortest_path = nx.shortest_path_length(G, source='NODE_START', target='NODE_END', weight='weight')
with open('/app/data/truth.txt', 'w') as f:
    f.write(str(round(true_shortest_path, 2)))
EOF

    python3 /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
