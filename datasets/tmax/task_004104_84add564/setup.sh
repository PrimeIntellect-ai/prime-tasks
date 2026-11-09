#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate the voicemail audio
    espeak -w /app/oncall_voicemail.wav "The root of trust is at backup server node eighty seven."

    # Generate the corpus
    cat << 'EOF' > /tmp/gen_data.py
import json
import os

def write_json(path, data):
    with open(path, 'w') as f:
        json.dump(data, f)

# Clean: DAGs with node_87
for i in range(20):
    data = {
        "nodes": ["node_1", "node_2", "node_87"],
        "edges": [
            {"from": "node_1", "to": "node_2"},
            {"from": "node_2", "to": "node_87"}
        ]
    }
    write_json(f"/app/corpus/clean/clean_{i}.json", data)

# Evil: missing node_87
for i in range(10):
    data = {
        "nodes": ["node_1", "node_2", "node_3"],
        "edges": [
            {"from": "node_1", "to": "node_2"},
            {"from": "node_2", "to": "node_3"}
        ]
    }
    write_json(f"/app/corpus/evil/evil_missing_{i}.json", data)

# Evil: has cycles
for i in range(10):
    data = {
        "nodes": ["node_1", "node_2", "node_87"],
        "edges": [
            {"from": "node_1", "to": "node_2"},
            {"from": "node_2", "to": "node_87"},
            {"from": "node_87", "to": "node_1"}
        ]
    }
    write_json(f"/app/corpus/evil/evil_cycle_{i}.json", data)
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
