#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/telemetry.jsonl
{"timestamp": "2023-10-12T14:15:00Z", "action": "login", "x": 53.0, "y": 54.0}
{"timestamp": "2023-10-12T14:45:00Z", "action": "log\u0069n", "x": 47.0, "y": 46.0}
{"timestamp": "2023-10-12T14:50:00Z", "action": "log\u00XXin", "x": 0.0, "y": 0.0}
{"timestamp": "2023-10-12T14:55:00Z", "action": "logout", "x": 50.0, "y": 50.0}
{"timestamp": "2023-10-12T15:05:00Z", "action": "LOGIN", "x": 56.0, "y": 58.0}
{"timestamp": "2023-10-12T15:30:00Z", "action": "l\u006Fgin", "x": 44.0, "y": 42.0}
{"timestamp": "2023-10-12T15:40:00Z", "action": "fail\uZZZZ", "x": 10.0, "y": 10.0}
{"timestamp": "2023-10-13T09:12:00Z", "action": "login", "x": 50.0, "y": 60.0}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
