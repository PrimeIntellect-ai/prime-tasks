#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/audit_logs.jsonl
{"msg_id": "1", "sender": "alice@corp.com", "recipient": "bob@corp.com"}
{"msg_id": "2", "sender": "alice@corp.com", "recipient": "bob@corp.com"}
{"msg_id": "3", "sender": "alice@corp.com", "recipient": "bob@corp.com"}
{"msg_id": "4", "sender": "alice@corp.com", "recipient": "bob@corp.com"}
{"msg_id": "5", "sender": "alice@corp.com", "recipient": "charlie@corp.com"}
{"msg_id": "6", "sender": "alice@corp.com", "recipient": "charlie@corp.com"}
{"msg_id": "7", "sender": "alice@corp.com", "recipient": "charlie@corp.com"}
{"msg_id": "8", "sender": "bob@corp.com", "recipient": "charlie@corp.com"}
{"msg_id": "9", "sender": "bob@corp.com", "recipient": "charlie@corp.com"}
{"msg_id": "10", "sender": "bob@corp.com", "recipient": "charlie@corp.com"}
{"msg_id": "11", "sender": "bob@corp.com", "recipient": "charlie@corp.com"}
{"msg_id": "12", "sender": "bob@corp.com", "recipient": "charlie@corp.com"}
{"msg_id": "13", "sender": "charlie@corp.com", "recipient": "alice@corp.com"}
{"msg_id": "14", "sender": "david@corp.com", "recipient": "eve@corp.com"}
{"msg_id": "15", "sender": "david@corp.com", "recipient": "eve@corp.com"}
{"msg_id": "16", "sender": "david@corp.com", "recipient": "eve@corp.com"}
{"msg_id": "17", "sender": "david@corp.com", "recipient": "eve@corp.com"}
{"msg_id": "18", "sender": "eve@corp.com", "recipient": "david@corp.com"}
{"msg_id": "19", "sender": "eve@corp.com", "recipient": "david@corp.com"}
{"msg_id": "20", "sender": "eve@corp.com", "recipient": "david@corp.com"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
