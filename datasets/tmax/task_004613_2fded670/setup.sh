#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # Download and extract networkx 2.8.8
    cd /app
    wget https://github.com/networkx/networkx/archive/refs/tags/networkx-2.8.8.tar.gz
    tar -xzf networkx-2.8.8.tar.gz
    mv networkx-networkx-2.8.8 networkx-vendored
    rm networkx-2.8.8.tar.gz

    # Introduce the syntax error in setup.py (missing comma)
    sed -i 's/name=name,/name="networkx"/g' /app/networkx-vendored/setup.py
    sed -i 's/name="networkx",/name="networkx"/g' /app/networkx-vendored/setup.py

    # Install networkx temporarily to generate the corpus
    pip3 install networkx==2.8.8

    # Generate the corpus
    python3 -c "
import networkx as nx
import json
import os

# Evil graphs (path length <= 3)
for i in range(10):
    G = nx.DiGraph()
    G.add_node(1, status='sanctioned')
    G.add_node(2)
    G.add_node(3)
    G.add_node(4, status='cleared')
    # Path of length 3
    G.add_edges_from([(1,2), (2,3), (3,4)])
    with open(f'/app/corpus/evil/graph_{i}.json', 'w') as f:
        json.dump(nx.node_link_data(G), f)

# Clean graphs (path length >= 4 or disconnected)
for i in range(10):
    G = nx.DiGraph()
    G.add_node(1, status='sanctioned')
    G.add_node(2)
    G.add_node(3)
    G.add_node(4)
    G.add_node(5, status='cleared')
    # Path of length 4
    G.add_edges_from([(1,2), (2,3), (3,4), (4,5)])
    with open(f'/app/corpus/clean/graph_{i}.json', 'w') as f:
        json.dump(nx.node_link_data(G), f)
"

    # Uninstall networkx so the agent has to fix and install the vendored one
    pip3 uninstall -y networkx

    # Create the user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
