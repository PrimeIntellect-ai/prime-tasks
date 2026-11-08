#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    # Create directories
    mkdir -p /app/vendored/py-graph-ext-1.2/py_graph_ext
    mkdir -p /app/corpus/clean_samples
    mkdir -p /app/corpus/evil_samples
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create vendored package setup.py
    cat << 'EOF' > /app/vendored/py-graph-ext-1.2/setup.py
import os
import sys
from setuptools import setup, find_packages

if os.environ.get("BUILD_PY_GRAPH_EXT") != "1":
    sys.exit("Missing ENV_GRAPH variable")

setup(
    name="py-graph-ext",
    version="1.2",
    packages=find_packages(),
    install_requires=["networkx"],
)
EOF

    # Create vendored package init
    cat << 'EOF' > /app/vendored/py-graph-ext-1.2/py_graph_ext/__init__.py
from .graph import Graph
EOF

    # Create vendored package graph.py
    cat << 'EOF' > /app/vendored/py-graph-ext-1.2/py_graph_ext/graph.py
import networkx as nx
from .centrality import compute_betweenness

class Graph:
    def __init__(self):
        self._g = nx.Graph()

    def add_edge(self, u, v):
        self._g.add_edge(u, v)

    def add_node(self, u):
        self._g.add_node(u)

    def compute_betweenness(self):
        return compute_betweenness(self._g)
EOF

    # Create vendored package centrality.py with intentional syntax error
    cat << 'EOF' > /app/vendored/py-graph-ext-1.2/py_graph_ext/centrality.py
import networkx as nx

def compute_betweenness(graph)
    return nx.betweenness_centrality(graph)
EOF

    # Create dummy CSV files to satisfy basic operations if needed
    echo "source_id,target_id,amount,timestamp" > /app/corpus/clean_samples/sample1.csv
    echo "1,2,100,1000" >> /app/corpus/clean_samples/sample1.csv

    echo "source_id,target_id,amount,timestamp" > /app/corpus/evil_samples/sample1.csv
    echo "1,2,100000,1000" >> /app/corpus/evil_samples/sample1.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
