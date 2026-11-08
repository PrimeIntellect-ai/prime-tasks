#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk sed
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_events.jsonl
{"event_id": 1, "timestamp": 1600000000, "user_id": "user_a", "ip_address": "192.168.1.10", "duration_sec": 10, "event_type": "login"}
{"event_id": 2, "timestamp": 1600000010, "user_id": "user_a", "ip_address": "192.168.1.10", "duration_sec": 20, "event_type": "click"}
{"event_id": 3, "timestamp": 1600000020, "user_id": "user_a", "ip_address": "192.168.1.15", "duration_sec": 30, "event_type": "click"}
{"event_id": 4, "timestamp": 1600000030, "user_id": "user_a", "ip_address": "192.168.1.15", "duration_sec": 40, "event_type": "logout"}
{"event_id": 5, "timestamp": 1600000040, "user_id": "user_b", "ip_address": "10.0.0.5", "duration_sec": 5, "event_type": "login"}
{"event_id": 6, "timestamp": 1600000050, "user_id": "user_b", "ip_address": "10.0.0.5", "duration_sec": 100, "event_type": "system_ping"}
{"event_id": 7, "timestamp": 1600000060, "user_id": "user_b", "ip_address": "10.0.0.6", "duration_sec": 15, "event_type": "click"}
{"event_id": 8, "timestamp": 1600000070, "user_id": "user_c", "ip_address": "172.16.254.1", "duration_sec": 50, "event_type": "login"}
EOF
    chmod 644 /home/user/raw_events.jsonl

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
