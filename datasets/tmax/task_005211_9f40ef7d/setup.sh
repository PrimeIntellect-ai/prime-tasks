#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config_changes.jsonl
{"timestamp": "2023-10-01T00:15:00Z", "service": "auth-⚙️", "allocation": 100}
{"timestamp": 1696139100, "service": "auth-⚙️", "allocation": 200} 
{"timestamp": "2023-10-01T10:00:00Z", "service": "auth-⚙️", "allocation": 15000}
{"timestamp": "2023-10-01T20:30:00Z", "service": "auth-⚙️", "allocation": 50}
{"timestamp": 1696126200, "service": "db-東京", "allocation": 500}
{"timestamp": "2023-10-01T02:50:00Z", "service": "db-東京", "allocation": 600}
{"timestamp": 1696161600, "service": "db-東京", "allocation": -50}
EOF

    chmod -R 777 /home/user
