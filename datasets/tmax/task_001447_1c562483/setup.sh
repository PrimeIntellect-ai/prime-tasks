#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3
    pip3 install pytest networkx

    mkdir -p /app/corpora/evil /app/corpora/clean

    # Generate video
    ffmpeg -f lavfi -i testsrc=duration=60:size=320x240:rate=30 -c:v libx264 /app/data_feed.mp4

    # Generate database
    sqlite3 /app/metrics.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, hostname TEXT, region TEXT);
CREATE TABLE traffic_logs (id INTEGER PRIMARY KEY, source_node_id INTEGER, target_node_id INTEGER, bytes_transferred INTEGER, timestamp TEXT);
INSERT INTO nodes (id, hostname, region) VALUES (1, 'host1', 'us-east');
INSERT INTO traffic_logs (id, source_node_id, target_node_id, bytes_transferred, timestamp) VALUES (1, 1, 2, 1000, '2024-01-15 12:00:00');
EOF

    # Generate corpora
    python3 -c "
import json

clean_graph = {
    'nodes': [{'id': str(i)} for i in range(1, 6)],
    'edges': [{'source': str(i), 'target': str(i+1 if i < 5 else 1)} for i in range(1, 6)]
}
with open('/app/corpora/clean/graph1.json', 'w') as f:
    json.dump(clean_graph, f)

evil_graph_high_centrality = {
    'nodes': [{'id': str(i)} for i in range(1, 7)],
    'edges': [{'source': '1', 'target': str(i)} for i in range(2, 7)]
}
with open('/app/corpora/evil/graph1.json', 'w') as f:
    json.dump(evil_graph_high_centrality, f)

evil_graph_malformed = {
    'nodes': [{'id': '1'}],
    'edges': [{'source': '1'}] # missing target
}
with open('/app/corpora/evil/graph2.json', 'w') as f:
    json.dump(evil_graph_malformed, f)

evil_graph_missing_nodes = {
    'edges': [{'source': '1', 'target': '2'}]
}
with open('/app/corpora/evil/graph3.json', 'w') as f:
    json.dump(evil_graph_missing_nodes, f)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
