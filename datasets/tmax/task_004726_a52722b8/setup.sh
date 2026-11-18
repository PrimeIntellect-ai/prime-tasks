#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc build-essential
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/chat_logs.jsonl
{"session_id": "S1", "timestamp": "2023-10-01T10:00:00Z", "message": "Hello \\u3053\\u3093\\u306b\\u3061\\u306f"}
{"session_id": "S2", "timestamp": "2023-10-01T10:01:00Z", "message": "Foo \\u2163"}
{"session_id": "S1", "timestamp": "2023-10-01T10:05:00Z", "message": "Bye"}
EOF

    cat << 'EOF' > /home/user/tx_logs.jsonl
{"session_id": "S1", "timestamp": 1696154410, "amount": 10.5}
{"session_id": "S1", "timestamp": 1696154450, "amount": 5.0}
{"session_id": "S1", "timestamp": 1696154470, "amount": 100.0}
{"session_id": "S2", "timestamp": 1696154465, "amount": 20.0}
{"session_id": "S1", "timestamp": 1696154760, "amount": 9.9}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
