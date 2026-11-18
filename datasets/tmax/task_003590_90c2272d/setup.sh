#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs /home/user/data

    cat << 'EOF' > /home/user/logs/server_events.jsonl
{"user_id": 101, "event_type": "login", "timestamp": "2023-10-01T10:00:00Z"}
{"user_id": 102, "event_type": "click", "timestamp": "2023-10-01T10:05:00Z", "payload": "bad \u00XX data"}
{"user_id": 101, "event_type": "purchase", "timestamp": "2023-10-01T10:10:00Z"}
{"user_id": 103, "timestamp": "2023-10-01T10:15:00Z"} 
{"user_id": 104, "event_type": "login", "timestamp": "2023-10-01T10:20:00Z"}
{"user_id": 102, "event_type": "login", "timestamp": "2023-10-01T10:25:00Z", "note": "good \u0032 unicode"}
{"user_id": 101, "event_type": "click", "timestamp": "2023-10-01T10:30:00Z"}
{"user_id": 104, "event_type": "purchase", "timestamp": "2023-10-01T10:35:00Z"}
EOF

    cat << 'EOF' > /home/user/data/user_metadata.csv
user_id,region
101,NA
102,EU
103,APAC
104,EU
EOF

    chmod -R 777 /home/user
