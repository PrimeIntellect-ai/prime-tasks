#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl jq
pip3 install pytest Flask==2.0.1 networkx==2.6.3

mkdir -p /app/backup-lineage-server

cat << 'EOF' > /app/backup-lineage-server/requirements.txt
Flask==2.0.1
networkx==2.6.3
EOF

cat << 'EOF' > /app/backup-lineage-server/server.py
import os
import csv
from flask import Flask, jsonify
import networkx as nx

app = Flask(__name__)
G = nx.DiGraph()

# PERTURBATION 1: Hardcoded path instead of using os.environ.get('DATA_PATH', '/home/user/processed_graph.csv')
DATA_FILE = "/var/lib/backups/data.csv"

def load_graph():
    with open(DATA_FILE, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            b_id = row['backup_id']
            p_id = row['parent_backup_id']
            # PERTURBATION 2: Skipping nodes if parent is empty prevents root nodes from existing in graph
            if not p_id:
                continue 
            G.add_node(b_id)
            G.add_node(p_id)
            # Edge points from child to parent for ancestor queries
            G.add_edge(b_id, p_id)

@app.route('/lineage/<backup_id>')
def get_lineage(backup_id):
    if backup_id not in G:
        return jsonify({"error": "Not found"}), 404
    # return list of ancestors (parents, grandparents)
    ancestors = list(nx.descendants(G, backup_id))
    # Note: descendants is used because edges point from child to parent
    return jsonify(ancestors)

if __name__ == '__main__':
    load_graph()
    app.run(host='127.0.0.1', port=9090)
EOF

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/manifests.jsonl
{"_id": "bck_001", "metadata": {"parent": null, "size": 1024}, "state": "SUCCESS"}
{"_id": "bck_002", "metadata": {"parent": "bck_001", "size": 2048}, "state": "SUCCESS"}
{"_id": "bck_003", "metadata": {"parent": "bck_002", "size": 4096}, "state": "SUCCESS"}
{"_id": "bck_004", "metadata": {"parent": "bck_003", "size": 8192}, "state": "SUCCESS"}
{"_id": "bck_005", "metadata": {"parent": "bck_004", "size": 16384}, "state": "FAILED"}
EOF

chmod -R 777 /app
chmod -R 777 /home/user
