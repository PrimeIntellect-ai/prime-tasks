#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/chat_stream.jsonl
{"id": "msg_01", "timestamp": 1000, "text": "Buy crypto now!!"}
{"id": "msg_02", "timestamp": 1010, "text": "Hello everyone."}
{"id": "msg_03", "timestamp": 1030, "text": "Búy cryptö nöw!"}
{"id": "msg_04", "timestamp": 1065, "text": "buy crypto now"}
{"id": "msg_05", "timestamp": 1100, "text": "Hello everyone."}
{"id": "msg_06", "timestamp": 1110, "text": "buy cryptos now"}
{"id": "msg_07", "timestamp": 1115, "text": "A"}
{"id": "msg_08", "timestamp": 1116, "text": "B"}
{"id": "msg_09", "timestamp": 1160, "text": "buy cryptos now!!!"}
EOF

    cat << 'EOF' > /home/user/.expected_flagged_messages.csv
id,matched_id,similarity_score
msg_03,msg_01,1.000
msg_04,msg_03,1.000
msg_06,msg_04,0.769
msg_09,msg_06,1.000
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
