#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create vendored package
    mkdir -p /app/graph-backup-lib/graph_backup_lib
    cat << 'EOF' > /app/graph-backup-lib/setup.py
from setuptools import setup, find_packages

setup(
    name='graph-backup-lib',
    version='1.0.0',
    packages=find_packages(),
)
EOF

    cat << 'EOF' > /app/graph-backup-lib/graph_backup_lib/__init__.py
import os

if os.environ.get("ENV") == "PROD":
    raise Exception("Invalid env")

def init_lib(
EOF

    cat << 'EOF' > /app/graph-backup-lib/graph_backup_lib/parser.py
import json

def parse_graph(filepath):
    with open(filepath, 'r') as f:
        return json.load(f)
EOF

    # Create directories
    mkdir -p /home/user/data/clean_manifests
    mkdir -p /home/user/data/evil_manifests

    # Create 5 clean manifests
    for i in 1 2 3 4 5; do
        cat << EOF > /home/user/data/clean_manifests/clean_${i}.json
{
  "nodes": [
    {"id": "A", "timestamp": "1672531200", "checksum": "abc"},
    {"id": "B", "timestamp": "1672531201", "checksum": "def"}
  ],
  "edges": [
    {"from": "A", "to": "B"}
  ]
}
EOF
    done

    # Create 5 evil manifests
    for i in 1 2 3 4 5; do
        cat << EOF > /home/user/data/evil_manifests/evil_${i}.json
{
  "nodes": [
    {"id": "A", "timestamp": "1672531200", "checksum": "abc"},
    {"id": "B", "timestamp": "1672531201"}
  ],
  "edges": [
    {"from": "A", "to": "B"},
    {"from": "B", "to": "A"}
  ]
}
EOF
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
