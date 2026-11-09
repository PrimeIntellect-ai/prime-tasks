#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/events_1.csv
timestamp,user_id,action
2023-10-15T08:15:30Z,101,click
2023-10-15T08:45:00Z,102,click
2023-10-15T09:05:00Z,101,view
2023-10-15T09:59:59Z,106,purchase
EOF

    cat << 'EOF' > /home/user/data/events_2.jsonl
{"timestamp": "2023-10-15T08:20:00Z", "user_id": 103, "action": "click"}
{"timestamp": "2023-10-15T08:30:00Z", "user_id": 104, "action": "view", "note": "bad unicode \uZZZZ"}
{"timestamp": "2023-10-15T09:15:00Z", "user_id": 105, "action": "click"}
{"timestamp": "2023-10-15T10:05:00Z", "user_id": 107, "action": "purchase"}
{"timestamp": "2023-10-15T10:10:00Z", "user_id": 108, "action": "view", "note": "another bad \uXX"}
{"timestamp": "2023-10-15T10:15:00Z", "user_id": 109, "action": "view"}
EOF

    chmod -R 777 /home/user
