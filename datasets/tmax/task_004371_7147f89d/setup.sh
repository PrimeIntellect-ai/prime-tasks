#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ curl wget
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.txt
[2023-10-01T10:00:01Z] INFO {"user": "alice", "msg": "hi", "declared_len": 2}
[2023-10-01T10:00:02Z] INFO {"user": "bob", "msg": "café", "declared_len": 4}
[2023-10-01T10:00:03Z] ERROR {"user": "sys", "msg": "fail", "declared_len": 4}
[2023-10-01T10:00:04Z] INFO {"user": "charlie", "msg": "こんにちは", "declared_len": 5}
[2023-10-01T10:00:05Z] INFO {"user": "dave", "msg": "🚀🚀🚀", "declared_len": 3}
[2023-10-01T10:00:06Z] INFO {"user": "eve", "msg": "hello", "declared_len": 99}
[2023-10-01T10:00:07Z] INFO {"user": "frank", "msg": "This is a very long message that should trigger the anomaly detector because it is much longer than the previous ones.", "declared_len": 118}
[2023-10-01T10:00:08Z] INFO {"user": "grace", "msg": "ok", "declared_len": 2}
EOF

    chmod -R 777 /home/user
