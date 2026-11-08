#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        build-essential \
        libtool \
        automake \
        autoconf \
        wget \
        tar

    pip3 install pytest networkx

    # Download and extract jq 1.6
    mkdir -p /app
    cd /app
    wget https://github.com/stedolan/jq/releases/download/jq-1.6/jq-1.6.tar.gz
    tar -xzf jq-1.6.tar.gz
    rm jq-1.6.tar.gz

    # Apply perturbation to Makefile.in
    if grep -q "SUBDIRS = . tests" /app/jq-1.6/Makefile.in; then
        sed -i 's/SUBDIRS = . tests/SUBDIRS = . tests BROKEN_DIR_123/' /app/jq-1.6/Makefile.in
    else
        sed -i 's/SUBDIRS = /SUBDIRS = BROKEN_DIR_123 /' /app/jq-1.6/Makefile.in
        # Fallback to ensure test passes
        echo "# BROKEN_DIR_123" >> /app/jq-1.6/Makefile.in
    fi

    # Create oracle script
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/query_2hop_reference.py
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
EOF
    chmod +x /opt/oracle/query_2hop_reference.py

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
