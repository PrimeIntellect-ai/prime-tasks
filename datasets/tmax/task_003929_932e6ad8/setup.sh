#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/incident_log.txt
GET /api/v1/status HTTP/1.1
Host: internal.corp.local
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)
Cookie: session_id=987654321; auth_token=f0VMRsYzZBY=; pref=dark
Accept: application/json
Connection: close
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
