#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_events.jsonl
{"user_id": "u1", "timestamp": "2023-10-01T10:00:00", "event_type": "view", "variant": "A"}
{"user_id": "u1", "timestamp": "2023-10-01T10:05:00", "event_type": "click", "variant": "A"}
{"user_id": "u2", "timestamp": "2023-10-01T10:01:00", "event_type": "view", "variant": "B"}
{"user_id": "u2", "timestamp": "2023-10-01T10:10:00", "event_type": "checkout", "variant": "B"}
{"user_id": "u3", "timestamp": "2023-10-01T10:02:00", "event_type": "view", "variant": "A"}
{"user_id": "u3", "timestamp": "2023-10-01T10:12:00", "event_type": "checkout", "variant": "A"}
{"user_id": "u4", "timestamp": "2023-10-01T10:03:00", "event_type": "view", "variant": "B"}
{"user_id": "u5", "timestamp": "2023-10-01T10:04:00", "event_type": "view", "variant": "A"}
{"user_id": "u6", "timestamp": "2023-10-01T10:05:00", "event_type": "view", "variant": "B"}
{"user_id": "u6", "timestamp": "2023-10-01T10:15:00", "event_type": "checkout", "variant": "B"}
{"user_id": "u7", "timestamp": "2023-10-01T10:06:00", "event_type": "view", "variant": "A"}
{"user_id": "u8", "timestamp": "2023-10-01T10:07:00", "event_type": "view", "variant": "B"}
EOF

    chmod -R 777 /home/user
