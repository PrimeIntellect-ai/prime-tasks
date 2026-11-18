#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils upx-ucl
    pip3 install pytest networkx pandas numpy pyinstaller

    mkdir -p /home/user/dataset
    mkdir -p /app

    # Create dataset generator
    cat << 'EOF' > /tmp/generate_dataset.py
import networkx as nx
import random
import pandas as pd
import os

os.makedirs('/home/user/dataset', exist_ok=True)
G = nx.barabasi_albert_graph(5000, 3)
edges = []
for u, v in G.edges():
    edges.append({'author_A': f"author_{u}", 'author_B': f"author_{v}", 'collaborations': random.randint(1, 10)})

df = pd.DataFrame(edges)
df.to_csv('/home/user/dataset/coauthors.csv', index=False)
EOF

    python3 /tmp/generate_dataset.py

    # Create node_scorer script
    cat << 'EOF' > /tmp/node_scorer.py
import sys
import pandas as pd
import networkx as nx

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    try:
        df = pd.read_csv(sys.argv[1])
        G = nx.from_pandas_edgelist(df, source='author_A', target='author_B', edge_attr='collaborations')
        pr = nx.pagerank(G, alpha=0.85, weight='collaborations')
        cc = nx.clustering(G)

        for node in G.nodes():
            score = 0.75 * pr[node] + 0.25 * cc[node]
            print(f"{node},{score}")
    except Exception as e:
        pass

if __name__ == '__main__':
    main()
EOF

    # Compile node_scorer
    cd /tmp
    pyinstaller --onefile node_scorer.py
    cp dist/node_scorer /app/node_scorer

    # Strip and pack (ignore errors if they fail, but try)
    strip /app/node_scorer || true
    upx /app/node_scorer || true

    # Clean up
    rm -rf /tmp/node_scorer* /tmp/build /tmp/dist /tmp/generate_dataset.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod 755 /app/node_scorer
