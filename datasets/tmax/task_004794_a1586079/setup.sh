#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gzip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/archive

    # Create raw dataset
    cat << 'EOF' > /home/user/raw_events.jsonl
{"event_id": "e1", "user_id": "u1", "email": "bob@domain.com", "event_type": "click", "timestamp": "2023-01-01T10:00:00Z", "message": "hello"}
{"event_id": "e2", "user_id": "u2", "email": "alice@domain.com", "event_type": "view", "timestamp": "2023-01-01T10:05:00Z", "message": "bad \uZZZZ string"}
{"event_id": "e1", "user_id": "u1", "email": "bob@domain.com", "event_type": "click", "timestamp": "2023-01-01T09:55:00Z", "message": "hello older"}
{"event_id": "e3", "user_id": "u3", "email": "charlie@test.org", "event_type": "purchase", "timestamp": "2023-01-01T10:10:00Z", "message": "ok"}
{"event_id": "e4", "user_id": "u4", "email": "dave@test.org", "event_type": "view", "timestamp": "2023-01-01T10:15:00Z", "message": "syntax error"
{"event_id": "e3", "user_id": "u3", "email": "charlie@test.org", "event_type": "purchase", "timestamp": "2023-01-01T10:12:00Z", "message": "ok later duplicate"}
EOF

    # Set permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
