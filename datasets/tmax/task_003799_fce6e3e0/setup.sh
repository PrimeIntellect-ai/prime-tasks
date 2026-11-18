#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar
    pip3 install pytest

    # Download and vendor networkx 2.8.8
    mkdir -p /app
    wget https://github.com/networkx/networkx/archive/refs/tags/networkx-2.8.8.tar.gz -O /tmp/nx.tar.gz
    tar -xzf /tmp/nx.tar.gz -C /tmp
    mv /tmp/networkx-networkx-2.8.8 /app/networkx-2.8.8
    rm /tmp/nx.tar.gz

    # Introduce syntax error in digraph.py
    sed -i 's/def add_node(self, node_for_adding, \*\*attr):/def add_node(self, node_for_adding, \*\*attr)/g' /app/networkx-2.8.8/networkx/classes/digraph.py

    # Create corpus directories
    mkdir -p /home/user/corpus/evil /home/user/corpus/clean

    # Generate evil corpus files with cycles
    echo '[{"source": "A", "target": "B"}, {"source": "B", "target": "A"}]' > /home/user/corpus/evil/1.json

    # Generate clean corpus files (DAGs)
    echo '[{"source": "A", "target": "B"}, {"source": "A", "target": "C"}]' > /home/user/corpus/clean/1.json

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app/networkx-2.8.8
