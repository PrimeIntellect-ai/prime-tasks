#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-client
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.ssh

    cat << 'EOF' > /home/user/raw_logs.jsonl
{"timestamp": "2023-10-01T12:00:00Z", "method": "GET", "url": "/profile", "headers": {"Host": "example.com", "Authorization": "Bearer super_secret_token_123", "Cookie": "theme=dark; session_id=9876543210abcdef; lang=en", "User-Agent": "curl/7.68.0"}}
{"timestamp": "2023-10-01T12:00:05Z", "method": "POST", "url": "/login", "headers": {"Host": "example.com", "Content-Type": "application/json"}}
{"timestamp": "2023-10-01T12:00:10Z", "method": "GET", "url": "/dashboard", "headers": {"Host": "example.com", "Cookie": "session_id=xyz123; active=true", "Authorization": "Basic YWRtaW46cGFzc3dvcmQ="}}
EOF

    chmod -R 777 /home/user
