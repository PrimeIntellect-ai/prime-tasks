#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jsonschema networkx

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import os

os.makedirs('/home/user/data', exist_ok=True)

# 1. Create SQLite DB
conn = sqlite3.connect('/home/user/data/servers.db')
c = conn.cursor()
c.execute('CREATE TABLE servers (server_id TEXT PRIMARY KEY, hostname TEXT, location TEXT)')
servers = [
    ('SRV-001', 'host-1', 'us-east-1'),
    ('SRV-042', 'host-42', 'us-west-2'), # The failing server
    ('SRV-099', 'host-99', 'eu-central-1'),
]
c.executemany('INSERT INTO servers VALUES (?,?,?)', servers)
conn.commit()
conn.close()

# 2. Create Services JSON
services = [
    {"service_id": "SVC-A", "service_name": "Auth", "priority": 100, "runs_on_server": "SRV-042", "depends_on": []},
    {"service_id": "SVC-B", "service_name": "Billing", "priority": 90, "runs_on_server": "SRV-001", "depends_on": ["SVC-A"]},
    {"service_id": "SVC-C", "service_name": "Catalog", "priority": 50, "runs_on_server": "SRV-099", "depends_on": []},
    {"service_id": "SVC-D", "service_name": "Dashboard", "priority": 10, "runs_on_server": "SRV-001", "depends_on": ["SVC-B"]},
    {"service_id": "SVC-E", "service_name": "Email", "priority": 90, "runs_on_server": "SRV-099", "depends_on": ["SVC-A"]},
    {"service_id": "SVC-F", "service_name": "Frontend", "priority": 100, "runs_on_server": "SRV-001", "depends_on": ["SVC-D", "SVC-C"]},
    {"service_id": "SVC-G", "service_name": "Gateway", "priority": 100, "runs_on_server": "SRV-042", "depends_on": []},
    {"service_id": "SVC-H", "service_name": "Helpdesk", "priority": 50, "runs_on_server": "SRV-001", "depends_on": ["SVC-G"]},
]
with open('/home/user/data/services.json', 'w') as f:
    json.dump(services, f)

# 3. Create Schema
schema = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "array",
    "items": {
        "type": "object",
        "properties": {
            "service_id": {"type": "string"},
            "service_name": {"type": "string"},
            "priority": {"type": "integer"},
            "impact_distance": {"type": "integer"},
            "server_location": {"type": "string"}
        },
        "required": ["service_id", "service_name", "priority", "impact_distance", "server_location"],
        "additionalProperties": False
    }
}
with open('/home/user/schema.json', 'w') as f:
    json.dump(schema, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
