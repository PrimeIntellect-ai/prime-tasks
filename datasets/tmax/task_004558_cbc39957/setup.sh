#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gcc
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/graph_backup

    # Generate audio alert
    espeak -w /app/incident_alert.wav "Corruption detected in DATABASE_SERVER nodes between timestamp 1600000000 and 1600086400."

    # Generate graph data
    cat << 'EOF' > /tmp/generate_graph.py
import csv

nodes_file = '/home/user/graph_backup/nodes.csv'
edges_file = '/home/user/graph_backup/edges.csv'

with open(nodes_file, 'w') as fn, open(edges_file, 'w') as fe:
    fn.write("node_id,node_type,timestamp,value\n")
    fe.write("source_id,target_id,relationship_type\n")

    # Target nodes
    fn.write("105,DATABASE_SERVER,1600000010,0.0\n")
    fn.write("208,DATABASE_SERVER,1600000020,0.0\n")

    # Neighbors for 105 (average = 42.5)
    fn.write("1001,OTHER,1600000001,40.0\n")
    fn.write("1002,OTHER,1600000002,45.0\n")
    fn.write("1003,OTHER,1600000003,42.5\n")
    fe.write("105,1001,DEPENDS_ON\n")
    fe.write("105,1002,DEPENDS_ON\n")
    fe.write("105,1003,DEPENDS_ON\n")

    # Neighbors for 208 (average = 38.1)
    fn.write("2001,OTHER,1600000001,38.0\n")
    fn.write("2002,OTHER,1600000002,38.2\n")
    fn.write("2003,OTHER,1600000003,38.1\n")
    fe.write("208,2001,DEPENDS_ON\n")
    fe.write("208,2002,DEPENDS_ON\n")
    fe.write("208,2003,DEPENDS_ON\n")

    # Dummy data to enforce indexing (100,000 nodes/edges)
    for i in range(3000, 103000):
        fn.write(f"{i},OTHER,1500000000,10.0\n")
        fe.write(f"{i},{i+1},OTHER_REL\n")
EOF

    python3 /tmp/generate_graph.py
    rm /tmp/generate_graph.py

    # Create user
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
