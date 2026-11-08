#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/graph_backup_store
    mkdir -p /verify
    mkdir -p /home/user

    # Create vendored package
    cat << 'EOF' > /app/graph_backup_store/__init__.py
from .store import GraphStore
EOF

    cat << 'EOF' > /app/graph_backup_store/store.py
import json

class GraphStore:
    def __init__(self, data_path):
        with open(data_path, 'r') as f:
            self.data = json.load(f)
        self._parent_index = {}
        self.build_index()

    def build_index(self):
        for node in self.data:
            self._parent_index[node['id']] = node.get('parent_id', node['id'])

    def get_parent(self, node_id):
        return self._parent_index.get(node_id)
EOF

    # Create dataset
    cat << 'EOF' > /tmp/generate_data.py
import json
import random

random.seed(42)
data = []
for i in range(1, 6):
    data.append({"id": f"bck_{i}"})

for i in range(6, 501):
    parent = random.randint(1, i - 1)
    data.append({"id": f"bck_{i}", "parent_id": f"bck_{parent}"})

with open('/home/user/backups.json', 'w') as f:
    json.dump(data, f)
EOF
    python3 /tmp/generate_data.py

    # Create oracle script
    cat << 'EOF' > /verify/oracle_get_lineage.py
import sys
import json

def get_lineage(node_id, data_path):
    with open(data_path, 'r') as f:
        data = json.load(f)

    parent_index = {}
    for node in data:
        parent_index[node['id']] = node.get('parent_id', None)

    lineage = []
    curr = node_id
    while curr is not None:
        lineage.append(curr)
        curr = parent_index.get(curr)

    print(" -> ".join(lineage))

if __name__ == "__main__":
    get_lineage(sys.argv[1], "/home/user/backups.json")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
