#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/telemetry.jsonl
{"ts": 1, "user_ip": "192.168.1.1", "metric": 10.0, "note": "ok"}
{"ts": 2, "user_ip": "192.168.1.2", "metric": 15.0, "note": "ok"}
{"ts": 3, "user_ip": "10.0.0.1", "metric": 99.0, "note": "broken \u123Z"}
{"ts": 4, "user_ip": "172.16.0.1", "metric": 20.0, "note": "ok"}
{"ts": 5, "user_ip": "192.168.1.5", "metric": 50.0, "note": "ok"}
{"ts": 6, "user_ip": "10.0.0.2", "metric": 100.0, "note": "broken \u999X"}
{"ts": 7, "user_ip": "192.168.1.7", "metric": 10.0, "note": "ok"}
EOF

    chmod -R 777 /home/user
