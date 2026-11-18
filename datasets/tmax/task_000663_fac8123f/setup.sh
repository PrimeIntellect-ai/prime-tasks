#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg jq
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate the voicemail audio
    espeak -w /app/voicemail.wav "Hey, it's Alex. The new graph index is corrupted. It's returning stale nodes. You need to write a script to filter the JSON responses. A response is stale, and should be rejected, if any node in the dependencies tree has a last_modified timestamp strictly older than its direct parent node's last_modified timestamp, AND the child node's status is set to 'active'. If it's stale, reject it. Otherwise, accept it."

    # Generate JSON documents
    cat << 'EOF' > /tmp/gen_json.py
import json
import os

clean_docs = [
    {
        "node_id": "root", "last_modified": 100, "status": "active",
        "dependencies": [
            {"node_id": "c1", "last_modified": 110, "status": "active", "dependencies": []}
        ]
    },
    {
        "node_id": "root", "last_modified": 100, "status": "active",
        "dependencies": [
            {"node_id": "c1", "last_modified": 90, "status": "inactive", "dependencies": []}
        ]
    }
]

evil_docs = [
    {
        "node_id": "root", "last_modified": 100, "status": "active",
        "dependencies": [
            {"node_id": "c1", "last_modified": 90, "status": "active", "dependencies": []}
        ]
    },
    {
        "node_id": "root", "last_modified": 100, "status": "active",
        "dependencies": [
            {"node_id": "c1", "last_modified": 110, "status": "active", "dependencies": [
                {"node_id": "c2", "last_modified": 105, "status": "active", "dependencies": []}
            ]}
        ]
    }
]

for i, doc in enumerate(clean_docs):
    with open(f"/app/corpora/clean/doc_{i}.json", "w") as f:
        json.dump(doc, f)

for i, doc in enumerate(evil_docs):
    with open(f"/app/corpora/evil/doc_{i}.json", "w") as f:
        json.dump(doc, f)
EOF
    python3 /tmp/gen_json.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
