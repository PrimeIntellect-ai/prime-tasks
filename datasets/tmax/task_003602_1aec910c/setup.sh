#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip parallel
    pip3 install pytest

    mkdir -p /home/user/logs/raw
    mkdir -p /home/user/logs/clean

    cat << 'EOF' > /home/user/logs/raw/server_01.log
[2023-10-12T10:00:00Z] 192.168.1.50 GET /api/user?email=john.doe@example.com 200 {"cc": "1234-5678-9012-3456"}
[2023-10-12T10:01:00Z] 10.0.0.15 POST /checkout 201 {"email": "admin@test.org", "cc": "1111-2222-3333-4444"}
[2023-10-12T10:02:00Z] 172.16.254.1 GET /index.html 404 {}
EOF

    cat << 'EOF' > /home/user/logs/raw/server_02.log
[2023-10-12T10:05:00Z] 8.8.8.8 GET /api/data 500 {"error": "bad payload"}
[2023-10-12T10:06:00Z] 192.168.1.250 PUT /update?user=jane_smith123@domain.net 200 {"cc": "9999-8888-7777-6666"}
[2023-10-12T10:07:00Z] 10.1.2.3 GET /health 200 {}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/logs
    chmod -R 777 /home/user
