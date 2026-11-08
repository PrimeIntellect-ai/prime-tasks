#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib

    mkdir -p /home/user

    cat << 'EOF' > /home/user/events.ndjson
{"user_id": "u1", "event_type": "click", "target_user": "u2"}
{"user_id": "u1", "event_type": "click", "target_user": "u2"}
{"user_id": "u1", "event_type": "click", "target_user": "u3"}
{"user_id": "u1", "event_type": "click", "target_user": "u4"}
{"user_id": "u2", "event_type": "click", "target_user": "u1"}
{"user_id": "u2", "event_type": "click", "target_user": "u3"}
{"user_id": "u2", "event_type": "click", "target_user": "u1"}
{"user_id": "u3", "event_type": "click", "target_user": "u1"}
{"user_id": "u3", "event_type": "click", "target_user": "u2"}
{"user_id": "u4", "event_type": "click", "target_user": "u1"}
{"user_id": "u4", "event_type": "click", "target_user": "u1"}
{"user_id": "u4", "event_type": "click", "target_user": "u2"}
{"user_id": "u5", "event_type": "click", "target_user": "u4"}
{"user_id": "u5", "event_type": "click", "target_user": "u1"}
{"user_id": "u5", "event_type": "click", "target_user": "u5"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
