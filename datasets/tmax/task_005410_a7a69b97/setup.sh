#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest flask fastapi uvicorn requests

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/incident_call.wav "Hey, this is operations. The implicit cross join took down the primary node. For the new API, make sure the authorization bearer token is iron_badger. I repeat, iron underscore badger."

    # Create backups.json
    cat << 'EOF' > /app/backups.json
[
  {"id": "B-001", "parent_id": null, "timestamp": "2023-10-01T10:00:00Z"},
  {"id": "B-002", "parent_id": "B-001", "timestamp": "2023-10-02T10:00:00Z"},
  {"id": "B-003", "parent_id": "B-002", "timestamp": "2023-10-03T10:00:00Z"},
  {"id": "B-004", "parent_id": "B-003", "timestamp": "2023-10-04T10:00:00Z"},
  {"id": "B-005", "parent_id": "B-004", "timestamp": "2023-10-05T10:00:00Z"},
  {"id": "B-099", "parent_id": "B-001", "timestamp": "2023-10-02T11:00:00Z"}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
