#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/config_exports
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/setup_data.py
import csv
import json

csv_data = [
    {"timestamp": "2023-10-01T10:00:00Z", "server_id": "srv1", "config_a": "v1", "config_b": "v2", "config_c": "", "description": "Normal update"},
    {"timestamp": "2023-10-01T11:00:00Z", "server_id": "srv1", "config_a": "v1", "config_b": "v2", "config_c": "", "description": "Redundant update"},
    {"timestamp": "2023-10-01T14:00:00Z", "server_id": "srv2", "config_a": "on", "config_b": "", "config_c": "yes", "description": "Multi-line\nDescription\nHere"},
    {"timestamp": "", "server_id": "srv3", "config_a": "1", "config_b": "2", "config_c": "3", "description": "Missing timestamp"},
    {"timestamp": "2023-10-02T09:00:00Z", "server_id": "", "config_a": "x", "config_b": "y", "config_c": "z", "description": "Missing server"}
]

with open('/home/user/config_exports/data1.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["timestamp", "server_id", "config_a", "config_b", "config_c", "description"])
    writer.writeheader()
    writer.writerows(csv_data)

json_data = [
    {"timestamp": "2023-10-02T10:00:00Z", "server_id": "srv1", "configs": {"config_a": "v1", "config_c": "v3"}, "description": "json update"},
    {"timestamp": "2023-10-02T12:00:00Z", "server_id": "srv1", "configs": {"config_b": "v2"}, "description": "json another"},
    {"timestamp": "2023-10-02T15:00:00Z", "server_id": "srv2", "configs": {"config_a": "on", "config_c": "yes"}, "description": "same as day 1"},
    {"timestamp": "2023-10-02T16:00:00Z", "server_id": "srv2", "configs": {}, "description": "empty configs"}
]

with open('/home/user/config_exports/data2.json', 'w') as f:
    json.dump(json_data, f)

EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
