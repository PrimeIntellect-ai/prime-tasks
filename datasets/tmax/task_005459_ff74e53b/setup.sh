#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/evidence
    cat << 'EOF' > /home/user/evidence/access.log
[2023-10-25T10:00:00Z] 192.168.1.105 GET /search?payload=PHNjcmlwdD5mZXRjaCgnaHR0cDovL2V2aWwtY29ycC5jb20nKTwvc2NyaXB0Pg==
[2023-10-25T10:01:22Z] 172.16.0.2 GET /search?payload=aGVsbG8gd29ybGQ=
[2023-10-25T10:05:11Z] 10.0.0.55 POST /api/v1/ping?payload=bHM7IGNhdCAvZXRjL3Bhc3N3ZA==
[2023-10-25T10:06:00Z] 192.168.1.105 GET /search?payload=PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
