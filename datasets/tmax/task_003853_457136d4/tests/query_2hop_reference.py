#!/usr/bin/env python3
import sys
import json
import networkx as nx

if len(sys.argv) != 3:
    sys.exit(1)

target = sys.argv[1]
graph_file = sys.argv[2]

G = nx.DiGraph()
try:
    with open(graph_file, 'r') as f:
        for line in f:
            if not line.strip(): continue
            data = json.loads(line)
            G.add_edge(data['source'], data['target'])
except Exception:
    sys.exit(1)

if target not in G:
    sys.exit(0)

preds = list(G.predecessors(target))
hop2 = set()
for p in preds:
    for pp in G.predecessors(p):
        hop2.add(pp)

if target in hop2:
    hop2.remove(target)

for node in sorted(list(hop2)):
    print(node)
