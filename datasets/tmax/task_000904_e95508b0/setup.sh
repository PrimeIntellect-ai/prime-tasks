#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask fastapi uvicorn networkx setuptools

    mkdir -p /app/backup_graph_lib-1.0.0/backup_graph_lib
    mkdir -p /app/data
    mkdir -p /app/config

    # Create the auth token
    echo "secret_dbre_token_7734" > /app/config/auth_token.txt

    # Create the perturbed setup.py
    cat << 'EOF' > /app/backup_graph_lib-1.0.0/setup.py
from setuptools import setup, find_packages

setup(
    name="backup_graph_lib",
    version="1.0.0",
    packages=find_packages(),
    install_requires=["networkkxx"], # Deliberate perturbation
)
EOF

    # Create dummy library init
    cat << 'EOF' > /app/backup_graph_lib-1.0.0/backup_graph_lib/__init__.py
def parse_graph(json_path):
    pass # Dummy stub
EOF

    # Create backup data
    cat << 'EOF' > /app/data/backups.json
{
    "nodes": [
        {"backup_id": "b1", "region": "us-east", "size_mb": 100, "timestamp": "2023-01-01T10:00:00Z"},
        {"backup_id": "b2", "region": "us-east", "size_mb": 150, "timestamp": "2023-01-02T10:00:00Z"},
        {"backup_id": "b3", "region": "us-east", "size_mb": 50, "timestamp": "2023-01-03T10:00:00Z"},
        {"backup_id": "b4", "region": "us-west", "size_mb": 200, "timestamp": "2023-01-01T10:00:00Z"},
        {"backup_id": "b5", "region": "us-west", "size_mb": 300, "timestamp": "2023-01-02T10:00:00Z"}
    ],
    "edges": [
        {"source": "b2", "target": "b1"},
        {"source": "b3", "target": "b1"},
        {"source": "b5", "target": "b4"}
    ]
}
EOF

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
