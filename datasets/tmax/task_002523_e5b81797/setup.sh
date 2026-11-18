#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget
    pip3 install pytest scipy

    mkdir -p /app
    cd /app
    wget https://github.com/networkx/networkx/archive/refs/tags/networkx-2.8.8.tar.gz
    tar -xzf networkx-2.8.8.tar.gz
    mv networkx-networkx-2.8.8 networkx_src
    rm networkx-2.8.8.tar.gz

    # Inject the typo into setup.py
    sed -i 's/install_requires=install_requires,/install_requires=["scpiy"],/g' /app/networkx_src/setup.py

    # Create oracle script
    mkdir -p /oracle
    cat << 'EOF' > /oracle/analyze.py
import sys
import networkx as nx
from scipy.stats import wasserstein_distance

def main():
    if len(sys.argv) != 2:
        sys.exit(1)
    seq = sys.argv[1]

    G = nx.MultiDiGraph()
    for i in range(len(seq) - 2):
        kmer = seq[i:i+3]
        G.add_edge(kmer[:2], kmer[1:])

    counts = {0:0, 1:0, 2:0, 3:0, 4:0}
    for node in G.nodes():
        deg = G.out_degree(node)
        if deg <= 4:
            counts[deg] += 1

    total_nodes = G.number_of_nodes()
    if total_nodes == 0:
        P = [1.0, 0.0, 0.0, 0.0, 0.0]
    else:
        P = [counts[i]/total_nodes for i in range(5)]

    Q = [0.05, 0.25, 0.40, 0.25, 0.05]

    dist = wasserstein_distance(
        u_values=[0, 1, 2, 3, 4],
        v_values=[0, 1, 2, 3, 4],
        u_weights=P,
        v_weights=Q
    )

    print(f"{dist:.6f}")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
