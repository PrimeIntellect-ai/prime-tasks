#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest networkx pandas numpy

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/meeting_recording.wav "Hey team, we need to calculate a custom influence metric for our network. Every node starts with an initial score of 100.0. In each step, a node keeps 20 percent of its current score, and distributes the remaining 80 percent evenly among all of its outgoing neighbors. If a node has no outgoing neighbors, it just keeps the 80 percent instead of distributing it. After the distribution phase of the step, every node gets a base addition of 5.0 points. Let's run this for exactly 15 iterations and output the final scores."

    # Python script to generate edges and calculate ground truth
    cat << 'EOF' > /app/generate_data.py
import networkx as nx
import pandas as pd
import numpy as np
import random

# Generate a random scale-free directed graph
random.seed(42)
np.random.seed(42)
G = nx.barabasi_albert_graph(1000, 2, seed=42)
DG = nx.DiGraph()
for u, v in G.edges():
    if random.random() > 0.5:
        DG.add_edge(u, v)
    else:
        DG.add_edge(v, u)

# Save edges.csv
edges = pd.DataFrame(DG.edges(), columns=['source', 'target'])
edges.to_csv('/app/edges.csv', index=False)

# Compute ground truth
nodes = list(DG.nodes())
scores = {n: 100.0 for n in nodes}

for _ in range(15):
    new_scores = {n: 0.0 for n in nodes}
    for n in nodes:
        out_edges = list(DG.successors(n))
        if len(out_edges) > 0:
            keep = scores[n] * 0.2
            dist = (scores[n] * 0.8) / len(out_edges)
            new_scores[n] += keep
            for neighbor in out_edges:
                new_scores[neighbor] += dist
        else:
            new_scores[n] += scores[n]

    for n in nodes:
        scores[n] = new_scores[n] + 5.0

df_scores = pd.DataFrame(list(scores.items()), columns=['node', 'score'])
df_scores.to_csv('/app/ground_truth_scores.csv', index=False)
EOF

    python3 /app/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
