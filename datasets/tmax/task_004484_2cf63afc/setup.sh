#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/traffic.log
GET /api/v1/users HTTP/1.1
Host: api.example.com
Authorization: Bearer 1a2b3c4d5e6f7a8b9c0d1a2b3c4d5e6f7a8b9c0d1a2b3c4d5e6f7a8b9c0d1a2b
Accept: application/json

POST /api/v1/update HTTP/1.1
Host: api.example.com
Authorization: Bearer ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
Content-Type: application/json

{"status": "active"}

GET /public/info HTTP/1.1
Host: api.example.com
Accept: */*
EOF

    chmod -R 777 /home/user
