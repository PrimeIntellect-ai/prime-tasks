#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest networkx pandas scipy

    mkdir -p /home/user/data
    mkdir -p /app/fast_graph_analytics-1.2.0/src
    mkdir -p /app/fast_graph_analytics-1.2.0/fast_graph_analytics
    mkdir -p /opt/reference

    cat << 'EOF' > /tmp/setup_env.py
import os
import json
import random
import networkx as nx
import pandas as pd

# Generate graph
G = nx.erdos_renyi_graph(100, 0.1, directed=True)
nodes = list(G.nodes())
nodes[0] = "HUB_001"
mapping = {i: nodes[i] for i in range(len(nodes))}
G = nx.relabel_nodes(G, mapping)

edges_data = []
for u, v in G.edges():
    tt = round(random.uniform(1.0, 100.0), 2)
    G[u][v]['travel_time'] = tt
    edges_data.append({'source': u, 'target': v, 'travel_time': tt})

nodes_data = [{'node_id': n, 'node_type': 'hub' if n == 'HUB_001' else 'dc', 'name': f'Node_{n}'} for n in G.nodes()]

pd.DataFrame(nodes_data).to_csv('/home/user/data/nodes.csv', index=False)
pd.DataFrame(edges_data).to_csv('/home/user/data/edges.csv', index=False)

# Compute golden reference
pr = nx.pagerank(G, alpha=0.85)
sp = nx.single_source_dijkstra_path_length(G, "HUB_001", weight='travel_time')

golden = {
    "pagerank": pr,
    "shortest_paths_from_HUB_001": sp
}
with open('/opt/reference/analysis_output_golden.json', 'w') as f:
    json.dump(golden, f)
EOF
    python3 /tmp/setup_env.py

    # Create fast_graph_analytics
    cat << 'EOF' > /app/fast_graph_analytics-1.2.0/setup.py
from setuptools import setup
from setuptools.command.build_py import build_py
import subprocess
import os
import shutil

class CustomBuild(build_py):
    def run(self):
        subprocess.check_call(['make', '-C', 'src'])
        super().run()
        shutil.copy('src/libpagerank.so', os.path.join(self.build_lib, 'fast_graph_analytics/'))

setup(
    name='fast_graph_analytics',
    version='1.2.0',
    packages=['fast_graph_analytics'],
    cmdclass={'build_py': CustomBuild},
    package_data={'fast_graph_analytics': ['*.so']},
)
EOF

    cat << 'EOF' > /app/fast_graph_analytics-1.2.0/src/Makefile
all:
	gcc -O3 -c pagerank.c -o pagerank.o
	gcc -shared -o libpagerank.so pagerank.o
EOF

    cat << 'EOF' > /app/fast_graph_analytics-1.2.0/src/pagerank.c
void dummy() {}
EOF

    cat << 'EOF' > /app/fast_graph_analytics-1.2.0/fast_graph_analytics/__init__.py
import ctypes
import os
import networkx as nx
import pandas as pd

class Graph:
    def __init__(self, G):
        self.G = G

def parse_graph(nodes_file, edges_file):
    edges = pd.read_csv(edges_file)
    G = nx.from_pandas_edgelist(edges, 'source', 'target', ['travel_time'], create_using=nx.DiGraph())
    return Graph(G)

def compute_pagerank(graph):
    lib_path = os.path.join(os.path.dirname(__file__), 'libpagerank.so')
    try:
        ctypes.CDLL(lib_path)
    except Exception as e:
        raise RuntimeError("Failed to load C extension: " + str(e))
    return nx.pagerank(graph.G, alpha=0.85)

def compute_shortest_paths(graph, source):
    return nx.single_source_dijkstra_path_length(graph.G, source, weight='travel_time')
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app/fast_graph_analytics-1.2.0
    chmod -R 777 /home/user
