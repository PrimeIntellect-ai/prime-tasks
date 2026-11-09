#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest jsonschema

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_env.py
import sqlite3
import json
import os

# 1. Create SQLite DB
db_path = "/home/user/backups.db"
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute("CREATE TABLE backups (id INTEGER PRIMARY KEY, name TEXT, size_mb REAL, current_node TEXT)")
c.execute("INSERT INTO backups (name, size_mb, current_node) VALUES ('auth_db_snapshot_2023', 5000.0, 'us-east-1')")
c.execute("INSERT INTO backups (name, size_mb, current_node) VALUES ('metrics_db_2023', 12000.0, 'eu-west-1')")
conn.commit()
conn.close()

# 2. Create Network Topology
topology = {
    "edges": [
        {"source": "us-east-1", "target": "eu-west-1", "latency_ms": 80, "bandwidth_mbps": 250},
        {"source": "us-east-1", "target": "us-west-2", "latency_ms": 60, "bandwidth_mbps": 500},
        {"source": "us-west-2", "target": "ap-northeast-1", "latency_ms": 120, "bandwidth_mbps": 100},
        {"source": "eu-west-1", "target": "ap-northeast-1", "latency_ms": 150, "bandwidth_mbps": 300},
        {"source": "us-east-1", "target": "ap-northeast-1", "latency_ms": 200, "bandwidth_mbps": 50}
    ]
}
with open("/home/user/network_topology.json", "w") as f:
    json.dump(topology, f)

# 3. Create JSON Schema
schema = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "properties": {
        "backup_name": {"type": "string"},
        "path": {
            "type": "array",
            "items": {"type": "string"}
        },
        "total_time_ms": {"type": "number"}
    },
    "required": ["backup_name", "path", "total_time_ms"],
    "additionalProperties": False
}
with open("/home/user/schema.json", "w") as f:
    json.dump(schema, f)
EOF

    python3 /tmp/setup_env.py
    rm /tmp/setup_env.py

    chmod -R 777 /home/user
